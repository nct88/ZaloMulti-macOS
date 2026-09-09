// InAppUpdater.swift
// ZaloMulti
//
// Engine tự động cập nhật kiểu Telegram:
// Tải .zip → giải nén → verify → thay thế app → khởi động lại.
// Không cần mở browser, không cần tải file thủ công.

import Foundation
import AppKit

/// Trạng thái cập nhật
enum UpdateState: Equatable {
    case idle
    case checking
    case available(version: String, notes: String)
    case downloading(progress: Double)
    case extracting
    case installing
    case restarting
    case failed(message: String)
    case upToDate
}

/// Engine xử lý toàn bộ flow auto-update
@MainActor
final class InAppUpdater: ObservableObject {
    static let shared = InAppUpdater()
    
    @Published var state: UpdateState = .idle
    @Published var downloadProgress: Double = 0
    @Published var showUpdateSheet = false
    
    /// Thông tin bản mới
    private var latestVersion: String = ""
    private var downloadURL: URL?
    private var releaseNotes: String = ""
    
    /// Download delegate
    private var downloadDelegate: DownloadDelegate?
    
    private init() {}
    
    // MARK: - Check for Updates
    
    /// Kiểm tra bản mới từ server
    func checkForUpdates(showUpToDatePrompt: Bool = false) {
        guard state == .idle || state == .upToDate || state.isFailed else { return }
        
        state = .checking
        
        Task {
            do {
                // API endpoint từ SecureConfig (encrypted), fallback nếu decrypt thất bại
                var apiURL = SecureConfig.githubAPIURL
                if apiURL.isEmpty {
                    // Fallback: decrypt thất bại (thường do Bundle ID debug khác production)
                    apiURL = "https://api.github.com/repos/nct88/ZaloMulti-macOS/releases/latest"
                    DiagnosticLogger.warning("UPDATE", "SecureConfig decrypt failed → dùng fallback URL")
                }
                DiagnosticLogger.info("UPDATE", "Check URL: \(apiURL)")
                guard let url = URL(string: apiURL) else {
                    if showUpToDatePrompt { state = .failed(message: "Không thể kết nối máy chủ") }
                    else { state = .idle }
                    return
                }
                
                var request = URLRequest(url: url)
                request.timeoutInterval = 15
                request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
                
                let (data, response) = try await URLSession.shared.data(for: request)
                
                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                    DiagnosticLogger.warning("UPDATE", "API error: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                    if showUpToDatePrompt { state = .failed(message: "Không thể kiểm tra cập nhật") }
                    else { state = .idle }
                    return
                }
                
                let release = try JSONDecoder().decode(GitHubReleaseV2.self, from: data)
                let latestVer = release.tagName
                    .replacingOccurrences(of: "v", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                
                let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
                
                DiagnosticLogger.info("UPDATE", "Current: \(currentVersion), Latest: \(latestVer)")
                
                if isNewerVersion(latest: latestVer, current: currentVersion) {
                    // Tìm asset .zip để tải
                    let zipAsset = release.assets?.first(where: { $0.name.hasSuffix(".zip") })
                    
                    latestVersion = latestVer
                    releaseNotes = release.body ?? "Hotfix bảo mật, cải thiện hiệu năng."
                    downloadURL = zipAsset.flatMap { URL(string: $0.browserDownloadUrl) }
                    
                    state = .available(version: latestVer, notes: releaseNotes)
                    showUpdateSheet = true
                    DiagnosticLogger.info("UPDATE", "Bản mới \(latestVer) sẵn sàng — hiện sheet")
                } else {
                    state = showUpToDatePrompt ? .upToDate : .idle
                }
                
            } catch {
                DiagnosticLogger.error("UPDATE", "Check update failed", error: error)
                if showUpToDatePrompt {
                    state = .failed(message: "Lỗi kiểm tra: \(error.localizedDescription)")
                } else {
                    state = .idle
                }
            }
        }
    }
    
    // MARK: - Perform Update (Telegram-style)
    
    /// Bắt đầu tải và cài đặt — gọi khi user nhấn "Cập nhật ngay"
    func performUpdate() {
        guard let url = downloadURL else {
            state = .failed(message: "Không tìm thấy link tải")
            return
        }
        
        state = .downloading(progress: 0)
        downloadProgress = 0
        
        Task {
            do {
                // Step 1: Tải .zip
                let zipPath = try await downloadUpdate(from: url)
                
                // Step 2: Giải nén
                state = .extracting
                let appPath = try await extractUpdate(zipPath: zipPath)
                
                // Step 3: Verify
                try verifyApp(at: appPath, expectedVersion: latestVersion)
                
                // Step 4: Cài đặt (thay thế app hiện tại)
                state = .installing
                try installUpdate(newAppPath: appPath)
                
                // Step 5: Cleanup & Relaunch
                try? FileManager.default.removeItem(at: zipPath)
                
                state = .restarting
                try await Task.sleep(for: .seconds(1))
                relaunchApp()
                
            } catch {
                DiagnosticLogger.error("UPDATE", "Update failed", error: error)
                state = .failed(message: error.localizedDescription)
            }
        }
    }
    
    /// Hủy download
    func cancelUpdate() {
        downloadDelegate?.session?.invalidateAndCancel()
        downloadDelegate = nil
        state = .idle
        showUpdateSheet = false
    }
    
    /// Reset state
    func dismiss() {
        state = .idle
        showUpdateSheet = false
    }
    
    // MARK: - Download with Progress
    
    private func downloadUpdate(from url: URL) async throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZaloMulti_update_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        let destPath = tempDir.appendingPathComponent("ZaloMulti_latest.zip")
        
        return try await withCheckedThrowingContinuation { continuation in
            let delegate = DownloadDelegate(
                destination: destPath,
                onProgress: { [weak self] progress in
                    Task { @MainActor in
                        self?.downloadProgress = progress
                        self?.state = .downloading(progress: progress)
                    }
                },
                onComplete: { result in
                    switch result {
                    case .success(let url):
                        continuation.resume(returning: url)
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
            )
            
            let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
            delegate.session = session
            
            let task = session.downloadTask(with: url)
            task.resume()
            
            self.downloadDelegate = delegate
        }
    }
    
    // MARK: - Extract
    
    private func extractUpdate(zipPath: URL) async throws -> URL {
        let extractDir = zipPath.deletingLastPathComponent().appendingPathComponent("extracted")
        try? FileManager.default.removeItem(at: extractDir)
        try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)
        
        // Dùng ditto để giải nén (macOS native, hỗ trợ resource forks)
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = ["-xk", zipPath.path, extractDir.path]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            
            process.terminationHandler = { proc in
                if proc.terminationStatus == 0 {
                    // Tìm .app trong thư mục giải nén
                    let fm = FileManager.default
                    if let items = try? fm.contentsOfDirectory(atPath: extractDir.path) {
                        for item in items where item.hasSuffix(".app") {
                            let appURL = extractDir.appendingPathComponent(item)
                            continuation.resume(returning: appURL)
                            return
                        }
                    }
                    continuation.resume(throwing: UpdateError.appNotFoundInZip)
                } else {
                    continuation.resume(throwing: UpdateError.extractionFailed)
                }
            }
            
            do { try process.run() } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    // MARK: - Verify
    
    private func verifyApp(at appPath: URL, expectedVersion: String) throws {
        let plistPath = appPath.appendingPathComponent("Contents/Info.plist")
        guard let plist = NSDictionary(contentsOf: plistPath),
              let version = plist["CFBundleShortVersionString"] as? String else {
            throw UpdateError.verificationFailed("Không đọc được version từ app mới")
        }
        
        DiagnosticLogger.info("UPDATE", "Verify: app version = \(version), expected = \(expectedVersion)")
        
        // Verify là macOS app bundle hợp lệ
        let binaryPath = appPath.appendingPathComponent("Contents/MacOS")
        guard FileManager.default.fileExists(atPath: binaryPath.path) else {
            throw UpdateError.verificationFailed("App bundle không hợp lệ")
        }
    }
    
    // MARK: - Install (Replace current app)
    
    private func installUpdate(newAppPath: URL) throws {
        let fm = FileManager.default
        let currentAppPath = Bundle.main.bundleURL
        _ = currentAppPath.lastPathComponent
        
        // Backup app cũ → Trash
        let backupName = "ZaloMulti_backup_\(Int(Date().timeIntervalSince1970)).app"
        let trashURL = fm.homeDirectoryForCurrentUser.appendingPathComponent(".Trash/\(backupName)")
        
        DiagnosticLogger.info("UPDATE", "Backup: \(currentAppPath.path) → \(trashURL.path)")
        
        do {
            // Move app cũ → trash
            try fm.moveItem(at: currentAppPath, to: trashURL)
            
            // Move app mới → vị trí cũ
            try fm.moveItem(at: newAppPath, to: currentAppPath)
            
            // Xóa quarantine
            let xattr = Process()
            xattr.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
            xattr.arguments = ["-r", "-d", "com.apple.quarantine", currentAppPath.path]
            xattr.standardOutput = FileHandle.nullDevice
            xattr.standardError = FileHandle.nullDevice
            try? xattr.run()
            xattr.waitUntilExit()
            
            DiagnosticLogger.success("UPDATE", "✅ App đã được cập nhật tại \(currentAppPath.path)")
            
        } catch {
            // Rollback: khôi phục từ backup
            DiagnosticLogger.error("UPDATE", "Install failed, rolling back", error: error)
            if fm.fileExists(atPath: trashURL.path) && !fm.fileExists(atPath: currentAppPath.path) {
                try? fm.moveItem(at: trashURL, to: currentAppPath)
            }
            throw UpdateError.installFailed(error.localizedDescription)
        }
    }
    
    // MARK: - Relaunch
    
    private func relaunchApp() {
        let appPath = Bundle.main.bundleURL.path
        
        // Dùng shell script để chờ app cũ thoát → mở app mới
        let script = """
        #!/bin/bash
        sleep 1
        open "\(appPath)"
        """
        
        let tempScript = FileManager.default.temporaryDirectory.appendingPathComponent("relaunch.sh")
        try? script.write(to: tempScript, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempScript.path)
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [tempScript.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        
        // Thoát app hiện tại
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NSApplication.shared.terminate(nil)
        }
    }
    
    // MARK: - Helpers
    
    private func isNewerVersion(latest: String, current: String) -> Bool {
        latest.compare(current, options: .numeric) == .orderedDescending
    }
}

// MARK: - Update Errors

enum UpdateError: LocalizedError {
    case appNotFoundInZip
    case extractionFailed
    case verificationFailed(String)
    case installFailed(String)
    case downloadFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .appNotFoundInZip: return "Không tìm thấy app trong file tải về"
        case .extractionFailed: return "Giải nén thất bại"
        case .verificationFailed(let msg): return "Xác minh thất bại: \(msg)"
        case .installFailed(let msg): return "Cài đặt thất bại: \(msg)"
        case .downloadFailed(let msg): return "Tải thất bại: \(msg)"
        }
    }
}

// MARK: - Download Delegate (Progress tracking)

private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let destination: URL
    let onProgress: @Sendable (Double) -> Void
    let onComplete: @Sendable (Result<URL, Error>) -> Void
    nonisolated(unsafe) weak var session: URLSession?
    
    init(destination: URL, onProgress: @escaping @Sendable (Double) -> Void, onComplete: @escaping @Sendable (Result<URL, Error>) -> Void) {
        self.destination = destination
        self.onProgress = onProgress
        self.onComplete = onComplete
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
            onComplete(.success(destination))
        } catch {
            onComplete(.failure(error))
        }
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        onProgress(min(progress, 1.0))
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        if let error = error {
            onComplete(.failure(error))
        }
    }
}

// MARK: - GitHub Release Model V2 (with assets)

struct GitHubReleaseV2: Codable {
    let tagName: String
    let htmlUrl: String
    let body: String?
    let assets: [GitHubAsset]?
    
    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlUrl = "html_url"
        case body
        case assets
    }
}

struct GitHubAsset: Codable {
    let name: String
    let browserDownloadUrl: String
    let size: Int?
    let contentType: String?
    
    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadUrl = "browser_download_url"
        case size
        case contentType = "content_type"
    }
}

// MARK: - UpdateState Extensions

extension UpdateState {
    var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }
    
    var displayText: String {
        switch self {
        case .idle: return ""
        case .checking: return "Đang kiểm tra..."
        case .available(let v, _): return "Có bản cập nhật v\(v)"
        case .downloading(let p): return "Đang tải... \(Int(p * 100))%"
        case .extracting: return "Đang giải nén..."
        case .installing: return "Đang cài đặt..."
        case .restarting: return "Khởi động lại..."
        case .failed(let msg): return "Lỗi: \(msg)"
        case .upToDate: return "Đã là bản mới nhất"
        }
    }
}
