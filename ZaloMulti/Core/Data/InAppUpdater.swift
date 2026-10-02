import Foundation
import AppKit

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

@MainActor
final class InAppUpdater: ObservableObject {
    static let shared = InAppUpdater()

    @Published var state: UpdateState = .idle
    @Published var downloadProgress: Double = 0
    @Published var showUpdateSheet = false

    private var latestVersion: String = ""
    private var downloadURL: URL?
    private var releaseNotes: String = ""

    private var downloadDelegate: DownloadDelegate?

    private init() {}

    func checkForUpdates(showUpToDatePrompt: Bool = false) {
        guard state == .idle || state == .upToDate || state.isFailed else { return }

        state = .checking

        Task {
            do {

                let apiURL = SecureConfig.githubAPIURL
                if apiURL.isEmpty {
                    DiagnosticLogger.warning("UPDATE", "SecureConfig decrypt thất bại → bỏ qua kiểm tra cập nhật")
                    if showUpToDatePrompt { state = .failed(message: "Không thể kết nối máy chủ") }
                    else { state = .idle }
                    return
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

    func performUpdate() {
        guard let url = downloadURL else {
            state = .failed(message: "Không tìm thấy link tải")
            return
        }

        state = .downloading(progress: 0)
        downloadProgress = 0

        Task {
            do {

                let zipPath = try await downloadUpdate(from: url)

                state = .extracting
                let appPath = try await extractUpdate(zipPath: zipPath)

                try verifyApp(at: appPath, expectedVersion: latestVersion)

                state = .installing
                try installUpdate(newAppPath: appPath)

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

    func cancelUpdate() {
        downloadDelegate?.session?.invalidateAndCancel()
        downloadDelegate = nil
        state = .idle
        showUpdateSheet = false
    }

    func dismiss() {
        state = .idle
        showUpdateSheet = false
    }

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

    private func extractUpdate(zipPath: URL) async throws -> URL {
        let extractDir = zipPath.deletingLastPathComponent().appendingPathComponent("extracted")
        try? FileManager.default.removeItem(at: extractDir)
        try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = ["-xk", zipPath.path, extractDir.path]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice

            process.terminationHandler = { proc in
                if proc.terminationStatus == 0 {

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

    private func verifyApp(at appPath: URL, expectedVersion: String) throws {
        let plistPath = appPath.appendingPathComponent("Contents/Info.plist")
        guard let plist = NSDictionary(contentsOf: plistPath),
              let version = plist["CFBundleShortVersionString"] as? String else {
            throw UpdateError.verificationFailed("Không đọc được version từ app mới")
        }

        DiagnosticLogger.info("UPDATE", "Verify: app version = \(version), expected = \(expectedVersion)")

        let binaryPath = appPath.appendingPathComponent("Contents/MacOS")
        guard FileManager.default.fileExists(atPath: binaryPath.path) else {
            throw UpdateError.verificationFailed("App bundle không hợp lệ")
        }
    }

    private func installUpdate(newAppPath: URL) throws {
        let fm = FileManager.default
        let currentAppPath = Bundle.main.bundleURL
        _ = currentAppPath.lastPathComponent

        let backupName = "ZaloMulti_backup_\(Int(Date().timeIntervalSince1970)).app"
        let trashURL = fm.homeDirectoryForCurrentUser.appendingPathComponent(".Trash/\(backupName)")

        DiagnosticLogger.info("UPDATE", "Backup: \(currentAppPath.path) → \(trashURL.path)")

        do {

            try fm.moveItem(at: currentAppPath, to: trashURL)

            try fm.moveItem(at: newAppPath, to: currentAppPath)

            let xattr = Process()
            xattr.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
            xattr.arguments = ["-r", "-d", "com.apple.quarantine", currentAppPath.path]
            xattr.standardOutput = FileHandle.nullDevice
            xattr.standardError = FileHandle.nullDevice
            try? xattr.run()
            xattr.waitUntilExit()

            DiagnosticLogger.success("UPDATE", "✅ App đã được cập nhật tại \(currentAppPath.path)")

        } catch {

            DiagnosticLogger.error("UPDATE", "Install failed, rolling back", error: error)
            if fm.fileExists(atPath: trashURL.path) && !fm.fileExists(atPath: currentAppPath.path) {
                try? fm.moveItem(at: trashURL, to: currentAppPath)
            }
            throw UpdateError.installFailed(error.localizedDescription)
        }
    }

    private func relaunchApp() {
        let appPath = Bundle.main.bundleURL.path

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

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NSApplication.shared.terminate(nil)
        }
    }

    private func isNewerVersion(latest: String, current: String) -> Bool {
        latest.compare(current, options: .numeric) == .orderedDescending
    }
}

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
