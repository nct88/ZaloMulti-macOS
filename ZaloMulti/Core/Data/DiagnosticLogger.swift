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
        // Đọc lossy: crash giữa lúc ghi có thể để lại byte UTF-8 dở dang
        guard let data = FileManager.default.contents(atPath: logFilePath) else {
            return "(Không thể đọc file log)"
        }
        return String(decoding: data, as: UTF8.self)
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
    
    fileprivate func flushQueue() {
        queue.sync {}
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

// MARK: - Flush

extension DiagnosticLogger {
    /// Chờ ghi hết log đang xếp hàng xuống file.
    static func flush() {
        shared.flushQueue()
    }
}

// MARK: - Diagnostic Tracer
//
// Bật khi build với cờ ZM_DIAG (bash build-dist.sh --diag) hoặc
// `defaults write <bundle-id> ZMDiagnosticMode -bool YES`.
// Ghi mọi click/phím, view nhận click, trạng thái cửa sổ và form "Thêm tài khoản".

@MainActor
enum DiagnosticTracer {
    static var isEnabled: Bool {
        #if ZM_DIAG
        return true
        #else
        return UserDefaults.standard.bool(forKey: "ZMDiagnosticMode")
        #endif
    }

    private static var eventMonitor: Any?
    private static var observers: [NSObjectProtocol] = []

    static func start() {
        guard isEnabled, eventMonitor == nil else { return }
        DiagnosticLogger.warning("DIAG", "Chế độ chẩn đoán BẬT — ghi mọi thao tác chuột/phím")
        logEnvironment()

        // CHỈ giám sát chuột. KHÔNG giám sát .keyDown: local monitor cho keyDown
        // làm chặn nhập liệu vào TextField (đã kiểm chứng: bản diag không gõ được,
        // bản thường gõ bình thường). Nội dung ô nhập được theo dõi qua onChange.
        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseUp, .rightMouseDown]
        ) { event in
            logEvent(event)
            return event
        }

        let nc = NotificationCenter.default
        let names: [Notification.Name] = [
            NSApplication.didBecomeActiveNotification,
            NSApplication.didResignActiveNotification,
            NSWindow.didBecomeKeyNotification,
            NSWindow.didResignKeyNotification,
            NSWindow.willBeginSheetNotification,
            NSWindow.didEndSheetNotification,
            NSWindow.willCloseNotification,
        ]
        for name in names {
            observers.append(nc.addObserver(forName: name, object: nil, queue: .main) { note in
                let window = note.object as? NSWindow
                MainActor.assumeIsolated {
                    let win = window.map { describe($0) } ?? "-"
                    DiagnosticLogger.info("DIAG", "\(name.rawValue) \(win)")
                }
            })
        }
    }

    // MARK: Logging

    private static func logEvent(_ event: NSEvent) {
        let kind: String
        switch event.type {
        case .leftMouseDown:  kind = "mouseDown"
        case .leftMouseUp:    kind = "mouseUp"
        case .rightMouseDown: kind = "rightMouseDown"
        case .keyDown:        kind = "keyDown keyCode=\(event.keyCode) mods=\(event.modifierFlags.rawValue)"
        default:              kind = "\(event.type.rawValue)"
        }

        guard let window = event.window else {
            DiagnosticLogger.info("EVENT", "\(kind) — không thuộc cửa sổ nào")
            return
        }

        var line = "\(kind) at=\(fmt(event.locationInWindow)) clicks=\(event.clickCount) win=\(describe(window))"
        if event.type != .keyDown, let content = window.contentView {
            let pointInSuper = content.superview?.convert(event.locationInWindow, from: nil)
                ?? event.locationInWindow
            if let hit = content.hitTest(pointInSuper) {
                line += " hit=\(viewChain(hit))"
            } else {
                line += " hit=nil"
            }
        }
        if event.type == .keyDown {
            line += " firstResponder=\(window.firstResponder.map { String(describing: type(of: $0)) } ?? "nil")"
        }
        DiagnosticLogger.info("EVENT", line)
    }

    private static func logEnvironment() {
        let b = Bundle.main
        let info = b.infoDictionary ?? [:]
        DiagnosticLogger.info("DIAG", "App \(info["CFBundleShortVersionString"] ?? "?") (\(info["CFBundleVersion"] ?? "?")) path=\(b.bundlePath)")
        DiagnosticLogger.info("DIAG", "Host=\(HostEnvironment.description) model=\(sysctlString("hw.model")) cpu=\(sysctlString("machdep.cpu.brand_string"))")
        DiagnosticLogger.info("DIAG", "macOS \(ProcessInfo.processInfo.operatingSystemVersionString) locale=\(Locale.current.identifier)")
        for screen in NSScreen.screens {
            DiagnosticLogger.info("DIAG", "Screen frame=\(fmt(screen.frame)) scale=\(screen.backingScaleFactor)")
        }
    }

    // MARK: Report

    /// Ghi snapshot trạng thái app, rồi xuất log + thông tin máy ra Desktop.
    static func exportReport(store: CloneStore) {
        snapshot(store: store, reason: "export")
        DiagnosticLogger.flush()

        let stamp = { () -> String in
            let f = DateFormatter()
            f.dateFormat = "yyyyMMdd-HHmmss"
            return f.string(from: Date())
        }()
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
        let outURL = desktop.appendingPathComponent("ZaloMulti-Log-\(stamp).txt")

        var report = "══════ ZaloMulti Diagnostic Report — \(stamp) ══════\n\n"
        report += "## Môi trường\n"
        report += shell("/usr/bin/sw_vers", [])
        report += "uname -m: \(shell("/usr/bin/uname", ["-m"]))"
        report += "Host: \(HostEnvironment.description)\n"
        report += "Model: \(sysctlString("hw.model")) — \(sysctlString("machdep.cpu.brand_string"))\n"
        report += "Diagnostic mode: \(isEnabled)\n\n"

        report += "## App\n"
        let appPath = Bundle.main.bundlePath
        report += "Path: \(appPath)\n"
        report += shell("/usr/bin/file", ["\(appPath)/Contents/MacOS/ZaloMulti"])
        report += shell("/usr/bin/codesign", ["-dv", appPath])
        report += "xattr: " + shell("/usr/bin/xattr", [appPath])
        report += "\n## Các bản ZaloMulti trong /Applications\n"
        let apps = (try? FileManager.default.contentsOfDirectory(atPath: "/Applications")) ?? []
        for name in apps where name.hasPrefix("ZaloMulti") && name.hasSuffix(".app") {
            let v = Bundle(path: "/Applications/\(name)")?.infoDictionary?["CFBundleShortVersionString"] ?? "?"
            report += "- \(name) v\(v)\n"
        }
        report += "\n## Zalo gốc\n"
        let zalo = Bundle(path: "/Applications/Zalo.app")?.infoDictionary
        report += "Zalo.app: \(zalo == nil ? "KHÔNG có" : "v\(zalo?["CFBundleShortVersionString"] ?? "?")")\n"

        report += "\n## Log hệ thống (ZaloMulti, 30 phút gần nhất)\n"
        report += shell("/usr/bin/log", ["show", "--last", "30m", "--style", "compact",
                                         "--predicate", "process BEGINSWITH \"ZaloMulti\""],
                        maxBytes: 400_000)

        report += "\n## Crash reports\n"
        let crashDir = "\(NSHomeDirectory())/Library/Logs/DiagnosticReports"
        let crashes = ((try? FileManager.default.contentsOfDirectory(atPath: crashDir)) ?? [])
            .filter { $0.hasPrefix("ZaloMulti") }
            .sorted()
            .suffix(3)
        if crashes.isEmpty { report += "(không có)\n" }
        for c in crashes {
            let text = (try? String(contentsOfFile: "\(crashDir)/\(c)", encoding: .utf8)) ?? ""
            report += "### \(c)\n\(text.prefix(30_000))\n"
        }

        report += "\n## zcm.log\n"
        let oldLog = FileManager.default.contents(atPath: DiagnosticLogger.logFilePath + ".old")
            .map { String(decoding: $0, as: UTF8.self) } ?? ""
        report += String(oldLog.suffix(200_000))
        report += DiagnosticLogger.readLogContents()

        do {
            try report.write(to: outURL, atomically: true, encoding: .utf8)
            DiagnosticLogger.success("DIAG", "Đã xuất báo cáo: \(outURL.path)")
            NSWorkspace.shared.activateFileViewerSelecting([outURL])
        } catch {
            DiagnosticLogger.error("DIAG", "Không xuất được báo cáo", error: error)
            let alert = NSAlert()
            alert.messageText = "Không lưu được file log"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    /// Ghi trạng thái hiện tại của store + toàn bộ cửa sổ.
    static func snapshot(store: CloneStore, reason: String) {
        DiagnosticLogger.info("SNAP", "[\(reason)] clones=\(store.clones.count) canAddMore=\(store.canAddMore) showAddCloneSheet=\(store.showAddCloneSheet) engineBusy=\(store.engine.isProcessing) appActive=\(NSApp.isActive)")
        for w in NSApp.windows {
            DiagnosticLogger.info("SNAP", "  window \(describe(w)) firstResponder=\(w.firstResponder.map { String(describing: type(of: $0)) } ?? "nil")")
        }
    }

    // MARK: Helpers

    static func describe(_ w: NSWindow) -> String {
        "#\(w.windowNumber) '\(w.title)' \(type(of: w)) frame=\(fmt(w.frame)) key=\(w.isKeyWindow) main=\(w.isMainWindow) visible=\(w.isVisible) level=\(w.level.rawValue) alpha=\(w.alphaValue) ignoresMouse=\(w.ignoresMouseEvents) sheet=\(w.attachedSheet != nil) modal=\(NSApp.modalWindow === w)"
    }

    private static func viewChain(_ view: NSView) -> String {
        var parts: [String] = []
        var v: NSView? = view
        while let cur = v, parts.count < 6 {
            parts.append("\(type(of: cur))\(cur.isHidden ? "(hidden)" : "")")
            v = cur.superview
        }
        return parts.joined(separator: " < ")
    }

    private static func fmt(_ p: NSPoint) -> String { "(\(Int(p.x)),\(Int(p.y)))" }
    private static func fmt(_ r: NSRect) -> String {
        "(\(Int(r.origin.x)),\(Int(r.origin.y)) \(Int(r.width))x\(Int(r.height)))"
    }

    private static func sysctlString(_ name: String) -> String {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return "?" }
        var buf = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buf, &size, nil, 0) == 0 else { return "?" }
        return String(cString: buf)
    }

    private static func shell(_ path: String, _ args: [String], maxBytes: Int = 50_000) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do {
            try p.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            let text = String(decoding: data.suffix(maxBytes), as: UTF8.self)
            return text.hasSuffix("\n") ? text : text + "\n"
        } catch {
            return "(\(path) lỗi: \(error.localizedDescription))\n"
        }
    }
}
