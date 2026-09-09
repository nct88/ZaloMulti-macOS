// ZaloCloneEngine.swift
// ZaloMulti
//
// Logic cốt lõi: detect Zalo gốc, copy bundle, đổi Bundle ID, re-sign.

import Foundation
import AppKit
import Darwin

/// Constants cho ZaloCloneEngine
enum ZaloPaths {
    static let zaloSourcePath = "/Applications/Zalo.app"
    static let zaloDataBase = "\(NSHomeDirectory())/Library/Application Support/ZaloMulti"
    static let cloneAppBase = "\(NSHomeDirectory())/Library/Application Support/ZaloMulti/Clones"
    static let originalBundleID = "com.vng.zalo"
    static let originalSendSocket = "/tmp/socketzalosend2021"
    static let originalRecvSocket = "/tmp/socketzalorecv2021"
}

/// Engine chính quản lý việc tạo và xoá Zalo clone
@MainActor
final class ZaloCloneEngine: ObservableObject {
    
    @Published var isProcessing = false
    @Published var progressMessage = ""
    
    // MARK: - Detect Zalo Source
    
    nonisolated func detectSourceZalo() -> (installed: Bool, version: String?, bundleID: String?) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: ZaloPaths.zaloSourcePath) else {
            DiagnosticLogger.warning("DETECT", "Zalo KHÔNG tìm thấy tại \(ZaloPaths.zaloSourcePath)")
            return (false, nil, nil)
        }
        
        let plistPath = "\(ZaloPaths.zaloSourcePath)/Contents/Info.plist"
        guard let plist = NSDictionary(contentsOfFile: plistPath) else {
            DiagnosticLogger.warning("DETECT", "Không đọc được Info.plist tại \(plistPath)")
            return (true, nil, nil)
        }
        
        let version = plist["CFBundleShortVersionString"] as? String
        let bundleID = plist["CFBundleIdentifier"] as? String
        
        DiagnosticLogger.info("DETECT", "Zalo OK — version=\(version ?? "?"), bundleID=\(bundleID ?? "?")")
        return (true, version, bundleID)
    }
    
    nonisolated var sourceZaloVersion: String? {
        detectSourceZalo().version
    }
    
    nonisolated var isElectronApp: Bool {
        let exists = FileManager.default.fileExists(
            atPath: "\(ZaloPaths.zaloSourcePath)/Contents/Resources/app.asar"
        )
        DiagnosticLogger.debug("DETECT", "Electron check: app.asar \(exists ? "tồn tại" : "KHÔNG tồn tại")")
        return exists
    }
    
    // MARK: - Create Clone
    
    func createClone(index: Int, name: String, phone: String = "") async throws -> CloneAccount {
        let clonePath = "\(ZaloPaths.cloneAppBase)/ZaloClone\(index).app"
        let bundleID = "\(ZaloPaths.originalBundleID).clone\(index)"
        let dataPath = "\(ZaloPaths.zaloDataBase)/Data/clone\(index)"
        
        DiagnosticLogger.info("CREATE", "Bắt đầu tạo clone #\(index): '\(name)'")
        DiagnosticLogger.info("CREATE", "Host: \(HostEnvironment.description) | OS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        if HostEnvironment.isRunningUnderRosetta {
            DiagnosticLogger.warning("CREATE", "App đang chạy qua Rosetta trên Apple Silicon — bản Intel dễ lỗi form/ký mã")
        }
        
        isProcessing = true
        progressMessage = "Đang chuẩn bị..."
        try? await Task.sleep(for: .milliseconds(400))
        
        do {
            progressMessage = "Tạo thư mục dữ liệu..."
            try Self.createDirectories(dataPath: dataPath)
            try? await Task.sleep(for: .milliseconds(300))
            
            progressMessage = "Sao chép Zalo app (APFS clone)..."
            try await Self.copyBundle(from: ZaloPaths.zaloSourcePath, to: clonePath)
            try? await Task.sleep(for: .milliseconds(300))
            
            progressMessage = "Đổi Bundle Identifier..."
            try Self.modifyBundleID(appPath: clonePath, newBundleID: bundleID)
            try? await Task.sleep(for: .milliseconds(300))
            
            progressMessage = "Đang vá Socket (app.asar)..."
            try Self.patchAsarSockets(appPath: clonePath, instanceIndex: index)
            try? await Task.sleep(for: .milliseconds(300))
            
            progressMessage = "Gắn môi trường cách ly..."
            try Self.injectCloneEnvironment(appPath: clonePath, dataPath: dataPath)
            try? await Task.sleep(for: .milliseconds(300))
            
            progressMessage = "Xoá quarantine..."
            try Self.removeQuarantine(appPath: clonePath)
            try? await Task.sleep(for: .milliseconds(300))
            
            progressMessage = "Re-sign ứng dụng..."
            try await Self.resignApp(appPath: clonePath)
            try? await Task.sleep(for: .milliseconds(300))
            
            isProcessing = false
            progressMessage = "Hoàn thành!"
            
            let account = CloneAccount(
                name: name,
                phoneNumber: phone,
                cloneIndex: index,
                bundleID: bundleID,
                appPath: clonePath,
                dataPath: dataPath,
                status: .stopped,
                avatarColor: CloneAccount.colorForIndex(index),
                createdAt: Date()
            )
            
            DiagnosticLogger.success("CREATE", "✅ Clone '\(name)' tạo thành công!")
            return account
            
        } catch {
            isProcessing = false
            progressMessage = "Lỗi: \(error.localizedDescription)"
            DiagnosticLogger.error("CREATE", "❌ Tạo clone THẤT BẠI", error: error)
            throw error
        }
    }
    
    // MARK: - Delete Clone
    
    nonisolated func deleteClone(_ clone: CloneAccount) throws {
        DiagnosticLogger.info("DELETE", "Xoá clone '\(clone.name)' (index=\(clone.cloneIndex))")
        let fm = FileManager.default
        
        if fm.fileExists(atPath: clone.appPath) {
            try fm.removeItem(atPath: clone.appPath)
        }
        if fm.fileExists(atPath: clone.dataPath) {
            try fm.removeItem(atPath: clone.dataPath)
        }
        DiagnosticLogger.success("DELETE", "Clone '\(clone.name)' đã xoá hoàn toàn")
    }
    
    // MARK: - Private Static Methods
    
    private nonisolated static func createDirectories(dataPath: String) throws {
        let fm = FileManager.default
        try fm.createDirectory(atPath: ZaloPaths.cloneAppBase, withIntermediateDirectories: true)
        try fm.createDirectory(atPath: dataPath, withIntermediateDirectories: true)
        let subdirs = [
            "Library/Application Support/Zalo",
            "Library/Application Support/ZaloData",
            "Library/Caches",
            "Library/Preferences",
            "Documents",
            "tmp"
        ]
        for subdir in subdirs {
            try fm.createDirectory(atPath: "\(dataPath)/\(subdir)", withIntermediateDirectories: true)
        }
    }
    
    private nonisolated static func copyBundle(from source: String, to destination: String) async throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: destination) {
            let chmodClean = Process()
            chmodClean.executableURL = URL(fileURLWithPath: "/bin/chmod")
            chmodClean.arguments = ["-R", "u+w", destination]
            try? chmodClean.run()
            chmodClean.waitUntilExit()
            try? fm.removeItem(atPath: destination)
        }
        
        // 1. Thử copy APFS clone siêu tốc (cp -c -R)
        let cpProcess = Process()
        cpProcess.executableURL = URL(fileURLWithPath: "/bin/cp")
        cpProcess.arguments = ["-c", "-R", source, destination]
        try? cpProcess.run()
        cpProcess.waitUntilExit()
        
        // 2. Nếu cp -c thất bại thì fallback sang rsync
        if cpProcess.terminationStatus != 0 {
            if fm.fileExists(atPath: destination) { try? fm.removeItem(atPath: destination) }
            let rsyncProcess = Process()
            rsyncProcess.executableURL = URL(fileURLWithPath: "/usr/bin/rsync")
            rsyncProcess.arguments = ["-a", source + "/", destination + "/"]
            try rsyncProcess.run()
            rsyncProcess.waitUntilExit()
            guard rsyncProcess.terminationStatus == 0 else {
                throw CloneError.copyFailed("rsync exit code \(rsyncProcess.terminationStatus)")
            }
        }
        
        // 3. Cấp quyền ghi toàn bộ file
        let chmodProc = Process()
        chmodProc.executableURL = URL(fileURLWithPath: "/bin/chmod")
        chmodProc.arguments = ["-R", "u+w", destination]
        try? chmodProc.run()
        chmodProc.waitUntilExit()
    }
    
    /// Giữ nguyên Mach-O `Contents/MacOS/Zalo` (bắt buộc trên Apple Silicon) và
    /// gắn HOME/TMPDIR qua LSEnvironment — không thay binary bằng script bash.
    private nonisolated static func injectCloneEnvironment(appPath: String, dataPath: String) throws {
        let binaryPath = "\(appPath)/Contents/MacOS/Zalo"
        guard MachOFile.isMachO(at: binaryPath) else {
            throw CloneError.copyFailed("Binary Zalo không phải Mach-O — không thể tạo clone trên chip này")
        }
        
        let origBinaryPath = "\(appPath)/Contents/MacOS/Zalo.orig"
        if FileManager.default.fileExists(atPath: origBinaryPath) {
            try? FileManager.default.removeItem(atPath: origBinaryPath)
        }
        
        let plistPath = "\(appPath)/Contents/Info.plist"
        guard let dict = NSMutableDictionary(contentsOfFile: plistPath) else {
            throw CloneError.plistNotFound
        }
        
        var env = dict["LSEnvironment"] as? [String: String] ?? [:]
        env["HOME"] = dataPath
        env["TMPDIR"] = "\(dataPath)/tmp"
        if env["MallocNanoZone"] == nil {
            env["MallocNanoZone"] = "0"
        }
        dict["LSEnvironment"] = env
        
        guard dict.write(toFile: plistPath, atomically: true) else {
            throw CloneError.plistWriteFailed
        }
        DiagnosticLogger.info("CREATE", "LSEnvironment HOME=\(dataPath)")
    }
    
    private nonisolated static func modifyBundleID(appPath: String, newBundleID: String) throws {
        let plistPath = "\(appPath)/Contents/Info.plist"
        guard FileManager.default.fileExists(atPath: plistPath) else { throw CloneError.plistNotFound }
        try runPlistBuddy(plistPath: plistPath, command: "Set :CFBundleIdentifier \(newBundleID)")
        _ = try? runPlistBuddy(plistPath: plistPath, command: "Delete :ElectronAsarIntegrity")
        
        // Đổi Bundle ID cho các Helper apps để đồng bộ
        let frameworksDir = "\(appPath)/Contents/Frameworks"
        let fm = FileManager.default
        if let contents = try? fm.contentsOfDirectory(atPath: frameworksDir) {
            for item in contents where item.hasSuffix(".app") {
                let helperPlist = "\(frameworksDir)/\(item)/Contents/Info.plist"
                if fm.fileExists(atPath: helperPlist) {
                    let suffix = item.replacingOccurrences(of: "Zalo Helper", with: "")
                        .replacingOccurrences(of: ".app", with: "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .replacingOccurrences(of: "(", with: "")
                        .replacingOccurrences(of: ")", with: "")
                    let helperID = suffix.isEmpty ? "\(newBundleID).helper" : "\(newBundleID).helper.\(suffix)"
                    _ = try? runPlistBuddy(plistPath: helperPlist, command: "Set :CFBundleIdentifier \(helperID)")
                    _ = try? runPlistBuddy(plistPath: helperPlist, command: "Delete :ElectronAsarIntegrity")
                }
            }
        }
    }
    
    private nonisolated static func runPlistBuddy(plistPath: String, command: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/libexec/PlistBuddy")
        process.arguments = ["-c", command, plistPath]
        let pipe = Pipe()
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw CloneError.plistWriteFailed }
    }
    
    // MARK: - Patch ASAR
    
    private nonisolated static func patchAsarSockets(appPath: String, instanceIndex: Int) throws {
        let asarPath = "\(appPath)/Contents/Resources/app.asar"
        
        guard FileManager.default.fileExists(atPath: asarPath) else {
            return
        }
        
        var data = try Data(contentsOf: URL(fileURLWithPath: asarPath))
        
        let sendOld = ZaloPaths.originalSendSocket
        let recvOld = ZaloPaths.originalRecvSocket
        
        let indexStr = String(format: "%04d", 2000 + instanceIndex)
        let sendNew = "/tmp/socketzalosend\(indexStr)"
        let recvNew = "/tmp/socketzalorecv\(indexStr)"
        
        assert(sendOld.count == sendNew.count, "Socket string length mismatch!")
        assert(recvOld.count == recvNew.count, "Socket string length mismatch!")
        
        data = binaryReplace(in: data, find: sendOld, replace: sendNew)
        data = binaryReplace(in: data, find: recvOld, replace: recvNew)
        
        try data.write(to: URL(fileURLWithPath: asarPath))
    }
    
    /// Binary replace — O(n) in-place cho same-length strings (socket paths)
    private nonisolated static func binaryReplace(in data: Data, find: String, replace: String) -> Data {
        guard let findData = find.data(using: .utf8),
              let replaceData = replace.data(using: .utf8) else { return data }
        
        // Same-length optimization: overwrite in-place, không realloc
        if findData.count == replaceData.count {
            var result = data
            result.withUnsafeMutableBytes { buffer in
                guard let ptr = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
                let len = buffer.count
                let findLen = findData.count
                guard findLen <= len else { return }
                
                findData.withUnsafeBytes { findPtr in
                    replaceData.withUnsafeBytes { replPtr in
                        guard let findBase = findPtr.baseAddress,
                              let replBase = replPtr.baseAddress else { return }
                        var i = 0
                        while i <= len - findLen {
                            if memcmp(ptr + i, findBase, findLen) == 0 {
                                memcpy(ptr + i, replBase, findLen)
                                i += findLen
                            } else {
                                i += 1
                            }
                        }
                    }
                }
            }
            return result
        }
        
        // Fallback: khác length (hiếm khi xảy ra)
        var result = data
        var searchRange = result.startIndex..<result.endIndex
        while let range = result.range(of: findData, in: searchRange) {
            result.replaceSubrange(range, with: replaceData)
            searchRange = range.upperBound..<result.endIndex
        }
        return result
    }
    
    private nonisolated static func removeQuarantine(appPath: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        process.arguments = ["-cr", appPath]
        try process.run()
        process.waitUntilExit()
        
        let fm = FileManager.default
        if let enumerator = fm.enumerator(atPath: appPath) {
            for case let file as String in enumerator {
                if (file as NSString).lastPathComponent.hasPrefix("._") {
                    try? fm.removeItem(atPath: "\(appPath)/\(file)")
                }
            }
        }
    }
    
    private nonisolated static func resignApp(appPath: String) async throws {
        let fm = FileManager.default
        
        // JIT + Hardened Runtime — bắt buộc để Electron/V8 chạy trên Apple Silicon
        let entitlementsContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>com.apple.security.cs.allow-jit</key>
            <true/>
            <key>com.apple.security.cs.allow-unsigned-executable-memory</key>
            <true/>
            <key>com.apple.security.cs.disable-library-validation</key>
            <true/>
            <key>com.apple.security.device.audio-input</key>
            <true/>
            <key>com.apple.security.device.camera</key>
            <true/>
        </dict>
        </plist>
        """
        
        let tempEntitlementsPath = "\(NSTemporaryDirectory())zalo_clone_entitlements_\(UUID().uuidString).plist"
        try entitlementsContent.write(toFile: tempEntitlementsPath, atomically: true, encoding: .utf8)
        defer {
            try? fm.removeItem(atPath: tempEntitlementsPath)
        }
        
        // Ký từ trong ra ngoài. Không dùng --deep (deprecated macOS 13+, làm sai identifier helper trên ARM).
        
        let libsDir = "\(appPath)/Contents/Frameworks/Electron Framework.framework/Versions/A/Libraries"
        if let libItems = try? fm.contentsOfDirectory(atPath: libsDir) {
            for lib in libItems where lib.hasSuffix(".dylib") {
                try? runCodesign(path: "\(libsDir)/\(lib)", throwOnError: false)
            }
        }
        
        let crashpadPath = "\(appPath)/Contents/Frameworks/Electron Framework.framework/Versions/A/Helpers/chrome_crashpad_handler"
        if fm.fileExists(atPath: crashpadPath) {
            try? runCodesign(path: crashpadPath, throwOnError: false)
        }
        
        let frameworksDir = "\(appPath)/Contents/Frameworks"
        if let contents = try? fm.contentsOfDirectory(atPath: frameworksDir) {
            for item in contents where item.hasSuffix(".framework") {
                try? runCodesign(path: "\(frameworksDir)/\(item)", throwOnError: false)
            }
            for item in contents where item.hasSuffix(".app") {
                try runCodesign(path: "\(frameworksDir)/\(item)", entitlementsPath: tempEntitlementsPath)
            }
        }
        
        let mainExec = "\(appPath)/Contents/MacOS/Zalo"
        if MachOFile.isMachO(at: mainExec) {
            try runCodesign(path: mainExec, entitlementsPath: tempEntitlementsPath)
        }
        
        let origBinaryPath = "\(appPath)/Contents/MacOS/Zalo.orig"
        if fm.fileExists(atPath: origBinaryPath), MachOFile.isMachO(at: origBinaryPath) {
            try? runCodesign(path: origBinaryPath, entitlementsPath: tempEntitlementsPath, throwOnError: false)
        }
        
        try runCodesign(path: appPath, entitlementsPath: tempEntitlementsPath)
        
        guard MachOFile.isMachO(at: mainExec) else {
            throw CloneError.codesignFailed("Main executable không còn là Mach-O sau khi ký mã")
        }
    }
    
    private nonisolated static func runCodesign(
        path: String,
        entitlementsPath: String? = nil,
        throwOnError: Bool = true
    ) throws {
        func invoke() throws -> (status: Int32, stderr: String) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
            var args = ["--force", "--sign", "-", "--options", "runtime"]
            if let entPath = entitlementsPath {
                args.append(contentsOf: ["--entitlements", entPath])
            }
            args.append(path)
            process.arguments = args
            let pipe = Pipe()
            process.standardError = pipe
            process.standardOutput = FileHandle.nullDevice
            try process.run()
            let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let stderr = String(data: errorData, encoding: .utf8) ?? ""
            return (process.terminationStatus, stderr)
        }
        
        var result = try invoke()
        
        if result.status != 0, result.stderr.lowercased().contains("detritus") {
            let xattr = Process()
            xattr.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
            xattr.arguments = ["-cr", path]
            try? xattr.run()
            xattr.waitUntilExit()
            result = try invoke()
        }
        
        if result.status != 0 && throwOnError {
            let trimmed = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            DiagnosticLogger.error("CODESIGN", "Fail \(path): \(trimmed)")
            throw CloneError.codesignFailed("[\(HostEnvironment.description)] \(trimmed.isEmpty ? "exit \(result.status)" : trimmed)")
        }
    }
}

// MARK: - Host / Mach-O helpers

enum HostEnvironment {
    static var machineArchitecture: String {
        var info = utsname()
        uname(&info)
        return withUnsafePointer(to: &info.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 256) {
                String(cString: $0)
            }
        }
    }
    
    static var isRunningUnderRosetta: Bool {
        var translated: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let result = sysctlbyname("sysctl.proc_translated", &translated, &size, nil, 0)
        return result == 0 && translated == 1
    }
    
    static var hasArm64Hardware: Bool {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let result = sysctlbyname("hw.optional.arm64", &value, &size, nil, 0)
        return result == 0 && value == 1
    }
    
    static var description: String {
        if isRunningUnderRosetta {
            return "\(machineArchitecture) via Rosetta (Apple Silicon)"
        }
        if hasArm64Hardware {
            return "arm64 (Apple Silicon native)"
        }
        return "\(machineArchitecture) (Intel)"
    }
}

enum MachOFile {
    static func isMachO(at path: String) -> Bool {
        guard let handle = FileHandle(forReadingAtPath: path) else { return false }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 4), data.count == 4 else { return false }
        let magic = data.withUnsafeBytes { ptr in
            ptr.load(as: UInt32.self)
        }
        switch magic {
        case 0xfeedface, 0xcefaedfe, 0xfeedfacf, 0xcffaedfe, 0xcafebabe, 0xbebafeca:
            return true
        default:
            return false
        }
    }
}

// MARK: - Errors
enum CloneError: LocalizedError, Sendable {
    case zaloNotFound
    case copyFailed(String)
    case plistNotFound
    case plistWriteFailed
    case codesignFailed(String)
    case launchFailed(String)
    case alreadyRunning
    
    var errorDescription: String? {
        switch self {
        case .zaloNotFound:       return "Không tìm thấy Zalo tại /Applications/Zalo.app"
        case .copyFailed(let e):  return "Lỗi sao chép: \(e)"
        case .plistNotFound:      return "Không tìm thấy Info.plist"
        case .plistWriteFailed:   return "Không thể ghi Info.plist"
        case .codesignFailed(let e): return "Lỗi ký mã: \(e)"
        case .launchFailed(let e):   return "Lỗi khởi chạy: \(e)"
        case .alreadyRunning:     return "Clone này đang chạy"
        }
    }
}
