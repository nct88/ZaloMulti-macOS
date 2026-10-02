import Foundation
import CryptoKit

@MainActor
final class MigrationManager {

    static let shared = MigrationManager()

    private static let currentMigrationVersion = 2
    private static let migrationVersionKey = "migration_version_v1"

    private static var appSupportDir: String {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return dir.appendingPathComponent("ZaloMulti").path
    }

    private static var logDir: String {
        "\(NSHomeDirectory())/Library/Logs/ZaloMulti"
    }

    private init() {}

    func runMigrations() {
        let currentVersion = UserDefaults.standard.integer(forKey: Self.migrationVersionKey)

        guard currentVersion < Self.currentMigrationVersion else {
            DiagnosticLogger.debug("MIGRATE", "Đã ở version \(currentVersion), không cần migrate")
            return
        }

        DiagnosticLogger.info("MIGRATE", "Bắt đầu migration v\(currentVersion) → v\(Self.currentMigrationVersion)")

        if currentVersion < 1 {
            migrateToV1()
        }
        if currentVersion < 2 {
            migrateToV2()
        }

        UserDefaults.standard.set(Self.currentMigrationVersion, forKey: Self.migrationVersionKey)
        DiagnosticLogger.success("MIGRATE", "Migration hoàn tất → v\(Self.currentMigrationVersion)")
    }

    private func migrateToV1() {
        DiagnosticLogger.info("MIGRATE", "V1: Cleanup dữ liệu plaintext...")

        let fm = FileManager.default

        let oldDonateCachePath = "\(Self.appSupportDir)/donate_status.json"
        if fm.fileExists(atPath: oldDonateCachePath) {
            secureDelete(atPath: oldDonateCachePath)
            DiagnosticLogger.info("MIGRATE", "Đã xóa donate_status.json plaintext")
        }

        sanitizeLogFiles()

        DiagnosticLogger.success("MIGRATE", "V1: Cleanup hoàn tất")
    }

    private func migrateToV2() {
        DiagnosticLogger.info("MIGRATE", "V2: Chuyển sang encrypted storage...")

        let fm = FileManager.default
        let oldPaths = [
            "\(Self.appSupportDir)/donate_status.json",
            "\(Self.appSupportDir)/donate_cache.json",
            "\(Self.appSupportDir)/donate_status.enc",
        ]

        for path in oldPaths {
            if fm.fileExists(atPath: path) {
                secureDelete(atPath: path)
            }
        }

        cleanupAvatarCaches()

        DiagnosticLogger.success("MIGRATE", "V2: Encrypted storage activated")
    }

    private func secureDelete(atPath path: String) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else { return }

        do {

            if let attrs = try? fm.attributesOfItem(atPath: path),
               let size = attrs[.size] as? Int, size > 0 {
                let randomData = Data((0..<size).map { _ in UInt8.random(in: 0...255) })
                try randomData.write(to: URL(fileURLWithPath: path))
            }
            try fm.removeItem(atPath: path)
        } catch {

            try? fm.removeItem(atPath: path)
        }
    }

    private func sanitizeLogFiles() {
        let fm = FileManager.default
        let logDir = Self.logDir

        guard fm.fileExists(atPath: logDir),
              let files = try? fm.contentsOfDirectory(atPath: logDir) else { return }

        var sensitivePatterns = ["HWID", "hwid", "Hardware UUID", "IOPlatformUUID", "donate_check"]

        if let w = SecureConfig.decrypt(SecureConfig._workersDev) { sensitivePatterns.append(w) }
        if let d = SecureConfig.decrypt(SecureConfig._socialDonate) { sensitivePatterns.append(d) }

        for file in files where file.hasSuffix(".log") || file.hasSuffix(".log.old") {
            let filePath = "\(logDir)/\(file)"
            guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else { continue }

            var sanitized = content
            for pattern in sensitivePatterns {
                sanitized = sanitized.components(separatedBy: "\n")
                    .map { line in
                        if line.contains(pattern) {
                            return "[REDACTED] — dòng chứa thông tin nhạy cảm đã bị xóa"
                        }
                        return line
                    }
                    .joined(separator: "\n")
            }

            if sanitized != content {
                try? sanitized.write(toFile: filePath, atomically: true, encoding: .utf8)
                DiagnosticLogger.info("MIGRATE", "Đã sanitize: \(file)")
            }
        }
    }

    private func cleanupAvatarCaches() {
        let fm = FileManager.default
        let dataDir = "\(Self.appSupportDir)/Data"

        guard fm.fileExists(atPath: dataDir),
              let cloneDirs = try? fm.contentsOfDirectory(atPath: dataDir) else { return }

        for dir in cloneDirs where dir.hasPrefix("clone") {
            let avatarCache = "\(dataDir)/\(dir)/avatar_cache.jpg"
            if fm.fileExists(atPath: avatarCache) {
                try? fm.removeItem(atPath: avatarCache)
            }
        }
    }

    func cleanupOldVersionData() {
        let fm = FileManager.default

        let legacyPaths = [
            "\(Self.appSupportDir)/donate_status.json",
            "\(Self.appSupportDir)/donate_cache.json",
        ]

        for path in legacyPaths {
            if fm.fileExists(atPath: path) {
                secureDelete(atPath: path)
                DiagnosticLogger.info("MIGRATE", "Cleaned up legacy: \(URL(fileURLWithPath: path).lastPathComponent)")
            }
        }

        let home = NSHomeDirectory()
        let defaultZaloData = "\(home)/Library/Application Support/ZaloData"
        let backupZaloData = "\(home)/Library/Application Support/ZaloData.original"

        if (try? fm.destinationOfSymbolicLink(atPath: defaultZaloData)) != nil {

            try? fm.removeItem(atPath: defaultZaloData)
            if fm.fileExists(atPath: backupZaloData) {
                try? fm.moveItem(atPath: backupZaloData, toPath: defaultZaloData)
                DiagnosticLogger.success("MIGRATE", "Gỡ symlink ZaloData gãy + phục hồi từ ZaloData.original")
            } else {
                DiagnosticLogger.success("MIGRATE", "Gỡ symlink ZaloData gãy — Zalo gốc sẽ tự tạo lại")
            }
        } else if !fm.fileExists(atPath: defaultZaloData), fm.fileExists(atPath: backupZaloData) {
            try? fm.moveItem(atPath: backupZaloData, toPath: defaultZaloData)
            DiagnosticLogger.success("MIGRATE", "Phục hồi ZaloData gốc từ ZaloData.original")
        }
    }
}
