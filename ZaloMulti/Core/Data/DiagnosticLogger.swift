// DiagnosticLogger.swift
// ZaloMulti
//
// Hệ thống ghi log chi tiết cho toàn bộ ứng dụng.
// Log file: ~/Library/Logs/ZaloMulti/zcm.log
//
// Rebuild v2.1 — lazy init, không phụ thuộc SecureConfig khi khởi tạo.

import Foundation
import AppKit
import os.log

/// Logger trung tâm — ghi ra cả Console (os_log) và file
final class DiagnosticLogger: @unchecked Sendable {
    
    // MARK: - Singleton
    static let shared = DiagnosticLogger()
    
    // MARK: - Log File Path
    static let logDirectory = "\(NSHomeDirectory())/Library/Logs/ZaloMulti"
    static let logFilePath = "\(logDirectory)/zcm.log"
    static let maxLogSize: UInt64 = 5 * 1024 * 1024  // 5 MB max
    
    // Lazy os_log — không gọi SecureConfig trong init
    private lazy var osLog: Logger = {
        let subsystem = SecureConfig.logSubsystem.isEmpty
            ? "com.zalomulti.app"
            : SecureConfig.logSubsystem
        return Logger(subsystem: subsystem, category: "App")
    }()
    
    private let fileHandle: FileHandle?
    private let dateFormatter: DateFormatter
    private let queue = DispatchQueue(label: "com.zcm.logger", qos: .utility)
    
    // MARK: - Init
    
    private init() {
        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        
        let fm = FileManager.default
        try? fm.createDirectory(atPath: Self.logDirectory, withIntermediateDirectories: true)
        Self.rotateIfNeeded()
        
        if !fm.fileExists(atPath: Self.logFilePath) {
            fm.createFile(atPath: Self.logFilePath, contents: nil)
        }
        
        fileHandle = FileHandle(forWritingAtPath: Self.logFilePath)
        fileHandle?.seekToEndOfFile()
        
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.1.0"
        writeRaw("""
        
        ════════════════════════════════════════════════════════════════
        ║  ZaloMulti v\(version) — Session Started
        ║  \(dateFormatter.string(from: Date()))
        ║  macOS \(ProcessInfo.processInfo.operatingSystemVersionString)
        ║  Host: \(HostEnvironment.description)
        ║  Log file: \(Self.logFilePath)
        ════════════════════════════════════════════════════════════════
        
        """)
    }
    
    deinit {
        writeRaw("\n═══ Session Ended: \(dateFormatter.string(from: Date())) ═══\n")
        fileHandle?.closeFile()
    }
    
    // MARK: - Public API
    
    static func info(_ tag: String, _ message: String, file: String = #file, line: Int = #line) {
        shared.log(level: .info, tag: tag, message: message, file: file, line: line)
    }
    
    static func success(_ tag: String, _ message: String, file: String = #file, line: Int = #line) {
        shared.log(level: .success, tag: tag, message: message, file: file, line: line)
    }
    
    static func warning(_ tag: String, _ message: String, file: String = #file, line: Int = #line) {
        shared.log(level: .warning, tag: tag, message: message, file: file, line: line)
    }
    
    static func error(_ tag: String, _ message: String, error: Error? = nil, file: String = #file, line: Int = #line) {
        var fullMessage = message
        if let err = error {
            fullMessage += " | Error: \(err.localizedDescription)"
        }
        shared.log(level: .error, tag: tag, message: fullMessage, file: file, line: line)
    }
    
    static func debug(_ tag: String, _ message: String, file: String = #file, line: Int = #line) {
        #if DEBUG
        shared.log(level: .debug, tag: tag, message: message, file: file, line: line)
        #endif
    }
    
    static func measure(_ tag: String, _ operation: String, block: () throws -> Void) rethrows {
        let start = CFAbsoluteTimeGetCurrent()
        try block()
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
        info(tag, "\(operation) — \(String(format: "%.1f", elapsed))ms")
    }
    
    static func readLogContents() -> String {
        (try? String(contentsOfFile: logFilePath, encoding: .utf8)) ?? "(Không thể đọc file log)"
    }
    
    static func openLogInFinder() {
        NSWorkspace.shared.selectFile(logFilePath, inFileViewerRootedAtPath: logDirectory)
    }
    
    // MARK: - Private
    
    private enum LogLevel: String {
        case info    = "INFO"
        case success = " OK "
        case warning = "WARN"
        case error   = "ERR!"
        case debug   = "DBUG"
    }
    
    private func log(level: LogLevel, tag: String, message: String, file: String, line: Int) {
        let timestamp = dateFormatter.string(from: Date())
        let fileName = (file as NSString).lastPathComponent
        let logLine = "[\(timestamp)] [\(level.rawValue)] [\(tag)] \(message)  ← \(fileName):\(line)\n"
        
        queue.async { [weak self] in
            self?.writeRaw(logLine)
        }
        
        switch level {
        case .info:    osLog.info("[\(tag)] \(message)")
        case .success: osLog.info("✅ [\(tag)] \(message)")
        case .warning: osLog.warning("⚠️ [\(tag)] \(message)")
        case .error:   osLog.error("❌ [\(tag)] \(message)")
        case .debug:   osLog.debug("🔍 [\(tag)] \(message)")
        }
    }
    
    private func writeRaw(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        fileHandle?.write(data)
    }
    
    // MARK: - Log Rotation
    
    private static func rotateIfNeeded() {
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: logFilePath),
              let size = attrs[.size] as? UInt64,
              size > maxLogSize else { return }
        
        let backupPath = logFilePath + ".old"
        try? fm.removeItem(atPath: backupPath)
        try? fm.moveItem(atPath: logFilePath, toPath: backupPath)
    }
}
