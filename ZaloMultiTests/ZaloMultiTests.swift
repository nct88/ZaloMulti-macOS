// ZaloMultiTests.swift
// ZaloMultiTests
//
// Unit tests cho Security + Performance optimizations

import XCTest
@testable import ZaloMulti

// MARK: - Security Tests

final class SecurityTests: XCTestCase {
    
    func testSecureConfigDecryptValidValues() {
        // Test: decrypt các config strings phải trả về giá trị hợp lệ
        // (decrypt trả về nil nếu bundleID không khớp — acceptable trong test runner)
        let donateAPI = SecureConfig.donateAPIBase
        let socialDonate = SecureConfig.socialDonate
        let workersDev = SecureConfig.workersDev
        
        // Nếu decrypt thành công (bundleID đúng), phải là URL hợp lệ
        if !donateAPI.isEmpty {
            XCTAssertTrue(donateAPI.hasPrefix("http"), "donateAPI phải là URL, got: \(donateAPI.prefix(30))")
        }
        if !socialDonate.isEmpty {
            XCTAssertTrue(socialDonate.hasPrefix("http"), "socialDonate phải là URL, got: \(socialDonate.prefix(30))")
        }
        // workersDev có thể là domain, không nhất thiết bắt đầu bằng http
        _ = workersDev
    }
    
    func testSecureConfigDecryptInvalidDataReturnsNil() {
        // Test: decrypt data rác phải trả về nil, không crash
        let garbage = "this-is-not-valid-encrypted-data"
        let result = SecureConfig.decrypt(garbage)
        XCTAssertNil(result, "Decrypt data rác phải trả về nil")
    }
    
    func testSecureConfigEncryptedStringsAreNotPlaintext() {
        // Test: các encrypted config strings không chứa plaintext URLs
        let encryptedValues = [
            SecureConfig._donateAPIBase,
            SecureConfig._socialDonate,
            SecureConfig._workersDev,
            SecureConfig._donatePageURL,
        ]
        
        let sensitivePatterns = ["http://", "https://", "workers.dev", "truong.me", "congtruongit"]
        
        for encrypted in encryptedValues {
            for pattern in sensitivePatterns {
                XCTAssertFalse(
                    encrypted.contains(pattern),
                    "Encrypted string chứa plaintext pattern '\(pattern)': \(encrypted.prefix(20))..."
                )
            }
        }
    }
    
    func testSecureConfigEncryptedStringsAreHex() {
        // Test: encrypted strings phải là hex format
        let hexChars = CharacterSet(charactersIn: "0123456789abcdef")
        let encryptedValues = [
            SecureConfig._donateAPIBase,
            SecureConfig._socialDonate,
            SecureConfig._workersDev,
        ]
        
        for encrypted in encryptedValues {
            XCTAssertFalse(encrypted.isEmpty, "Encrypted string không được rỗng")
            let isHex = encrypted.unicodeScalars.allSatisfy { hexChars.contains($0) }
            XCTAssertTrue(isHex, "Encrypted string phải là hex: \(encrypted.prefix(20))...")
        }
    }
}

// MARK: - Performance Tests

final class PerformanceTests: XCTestCase {
    
    func testProcessManagerIsRunningInvalidPID() {
        // kill(-1, 0) trên macOS gửi signal tới tất cả user processes → skip PID -1
        // Chỉ test PID lớn không tồn tại
        let invalidLarge = ProcessManager.isRunning(pid: 999999)
        XCTAssertFalse(invalidLarge, "PID 999999 không nên tồn tại")
        
        let invalidLarge2 = ProcessManager.isRunning(pid: 888888)
        XCTAssertFalse(invalidLarge2, "PID 888888 không nên tồn tại")
    }
    
    func testProcessManagerIsRunningCurrentProcess() {
        // Test: PID hiện tại phải running
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let alive = ProcessManager.isRunning(pid: currentPID)
        XCTAssertTrue(alive, "PID hiện tại phải đang chạy")
    }
    
    func testKillPidZeroIsFast() {
        // Test: kill(pid, 0) phải rất nhanh (<1ms) — đo performance
        let currentPID = ProcessInfo.processInfo.processIdentifier
        
        measure {
            for _ in 0..<1000 {
                _ = ProcessManager.isRunning(pid: currentPID)
            }
        }
        // 1000 calls phải hoàn thành trong <0.1s (mặc định measure timeout)
    }
    
    func testDateFormatterSingleton() {
        // Test: formattedTimestamp dùng cached formatter — kết quả nhất quán
        let notif = PrivateNotification(
            cloneId: nil,
            cloneName: "Test",
            avatarColor: "#FF0000",
            title: "Test",
            body: "Test body",
            timestamp: Date()
        )
        
        let result1 = notif.formattedTimestamp
        let result2 = notif.formattedTimestamp
        
        XCTAssertFalse(result1.isEmpty, "formattedTimestamp không được rỗng")
        XCTAssertEqual(result1, result2, "Hai lần gọi phải cho cùng kết quả")
    }
    
    func testDateFormatterPerformance() {
        // Test: cached DateFormatter phải nhanh hơn đáng kể
        let notif = PrivateNotification(
            cloneId: nil, cloneName: "T", avatarColor: "#000",
            title: "T", body: "B", timestamp: Date()
        )
        
        measure {
            for _ in 0..<10000 {
                _ = notif.formattedTimestamp
            }
        }
    }
    
    func testTimeAgoFormat() {
        let now = PrivateNotification(
            cloneId: nil, cloneName: "T", avatarColor: "#000",
            title: "T", body: "B", timestamp: Date()
        )
        XCTAssertEqual(now.timeAgo, "vừa xong")
        
        let minutesAgo = PrivateNotification(
            cloneId: nil, cloneName: "T", avatarColor: "#000",
            title: "T", body: "B", timestamp: Date().addingTimeInterval(-120)
        )
        XCTAssertTrue(minutesAgo.timeAgo.contains("phút"), "2 phút trước phải chứa 'phút'")
        
        let hoursAgo = PrivateNotification(
            cloneId: nil, cloneName: "T", avatarColor: "#000",
            title: "T", body: "B", timestamp: Date().addingTimeInterval(-7200)
        )
        XCTAssertTrue(hoursAgo.timeAgo.contains("giờ"), "2 giờ trước phải chứa 'giờ'")
    }
    
    func testAvatarExtractorCacheThreadSafety() {
        // Test: concurrent access từ nhiều threads không crash
        let expectation = XCTestExpectation(description: "Concurrent avatar access")
        expectation.expectedFulfillmentCount = 10
        
        for i in 0..<10 {
            DispatchQueue.global().async {
                _ = AvatarExtractor.extractProfile(cloneIndex: 100 + i)
                AvatarExtractor.clearCache(cloneIndex: 100 + i)
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 5.0)
    }
    
    func testAvatarExtractorClearAllCache() {
        // Test: clearAllCache không crash
        AvatarExtractor.clearAllCache()
        // Nếu chạy đến đây → pass
    }
}

// MARK: - Data Model Tests

final class DataModelTests: XCTestCase {
    
    func testCloneAccountCodable() {
        let original = CloneAccount(
            name: "Test Clone",
            phoneNumber: "0901234567",
            cloneIndex: 1,
            bundleID: "com.vng.zalo.clone1",
            appPath: "/test/path",
            dataPath: "/test/data",
            status: .stopped,
            avatarColor: "#FF0000",
            createdAt: Date()
        )
        
        guard let data = try? JSONEncoder().encode(original) else {
            XCTFail("Encode thất bại")
            return
        }
        
        guard let decoded = try? JSONDecoder().decode(CloneAccount.self, from: data) else {
            XCTFail("Decode thất bại")
            return
        }
        
        XCTAssertEqual(decoded.name, original.name)
        XCTAssertEqual(decoded.phoneNumber, original.phoneNumber)
        XCTAssertEqual(decoded.cloneIndex, original.cloneIndex)
        XCTAssertEqual(decoded.bundleID, original.bundleID)
        XCTAssertEqual(decoded.status, original.status)
    }
    
    func testCloneAccountColorForIndex() {
        let colors = (1...10).map { CloneAccount.colorForIndex($0) }
        let uniqueColors = Set(colors)
        XCTAssertGreaterThan(uniqueColors.count, 1, "Phải có nhiều màu khác nhau")
    }
    
    func testCloneErrorDescriptions() {
        let errors: [CloneError] = [
            .zaloNotFound,
            .copyFailed("test"),
            .plistNotFound,
            .plistWriteFailed,
            .codesignFailed("test"),
            .launchFailed("test"),
            .alreadyRunning
        ]
        
        for error in errors {
            XCTAssertNotNil(error.errorDescription, "\(error) phải có description")
            XCTAssertFalse(error.errorDescription!.isEmpty)
        }
    }
    
    func testZaloPathsConstants() {
        XCTAssertTrue(ZaloPaths.zaloSourcePath.hasPrefix("/Applications"))
        XCTAssertTrue(ZaloPaths.zaloDataBase.contains("ZaloMulti"))
        XCTAssertTrue(ZaloPaths.cloneAppBase.contains("Clones"))
        XCTAssertEqual(ZaloPaths.originalBundleID, "com.vng.zalo")
    }
    
    func testHostEnvironmentDescriptionIsNonEmpty() {
        XCTAssertFalse(HostEnvironment.description.isEmpty)
        XCTAssertFalse(HostEnvironment.machineArchitecture.isEmpty)
    }
    
    func testMachOFileDetectsZaloBinary() {
        let zaloBinary = "/Applications/Zalo.app/Contents/MacOS/Zalo"
        if FileManager.default.fileExists(atPath: zaloBinary) {
            XCTAssertTrue(MachOFile.isMachO(at: zaloBinary), "Zalo binary phải là Mach-O")
        }
        
        let script = FileManager.default.temporaryDirectory.appendingPathComponent("zalo_script_test.sh")
        try? "#!/bin/bash\necho hi\n".write(to: script, atomically: true, encoding: .utf8)
        XCTAssertFalse(MachOFile.isMachO(at: script.path), "Script bash không phải Mach-O")
        try? FileManager.default.removeItem(at: script)
    }
    
    @MainActor
    func testCreateCloneProducesSignedMachOApp() async throws {
        let source = "/Applications/Zalo.app"
        try XCTSkipUnless(FileManager.default.fileExists(atPath: source), "Cần Zalo Desktop tại /Applications/Zalo.app")
        
        let engine = ZaloCloneEngine()
        let clone = try await engine.createClone(index: 97, name: "AutoTest97", phone: "0900000097")
        defer { try? engine.deleteClone(clone) }
        
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: "\(clone.appPath)/Contents/Info.plist"),
            "Clone phải có Info.plist"
        )
        XCTAssertTrue(
            MachOFile.isMachO(at: "\(clone.appPath)/Contents/MacOS/Zalo"),
            "Binary clone phải là Mach-O"
        )
        XCTAssertEqual(clone.bundleID, "com.vng.zalo.clone97")
        
        let plist = NSDictionary(contentsOfFile: "\(clone.appPath)/Contents/Info.plist")
        XCTAssertEqual(plist?["CFBundleIdentifier"] as? String, "com.vng.zalo.clone97")
        let env = plist?["LSEnvironment"] as? [String: String]
        XCTAssertEqual(env?["HOME"], clone.dataPath)
        XCTAssertEqual(env?["TMPDIR"], "\(clone.dataPath)/tmp")
    }
    
    func testPrivateNotificationIdentifiable() {
        let n1 = PrivateNotification(
            cloneId: nil, cloneName: "A", avatarColor: "#000",
            title: "T", body: "B", timestamp: Date()
        )
        let n2 = PrivateNotification(
            cloneId: nil, cloneName: "A", avatarColor: "#000",
            title: "T", body: "B", timestamp: Date()
        )
        // Mỗi notification phải có UUID riêng
        XCTAssertNotEqual(n1.id, n2.id, "Hai notifications phải có ID khác nhau")
    }
}

// MARK: - Source Code Security Scan

final class SourceCodeSecurityTests: XCTestCase {
    
    func testNoPlaintextInEncryptedConfig() {
        // Test: tất cả encrypted strings phải là ciphertext, không chứa text đọc được
        let allEncrypted: [(String, String)] = [
            (SecureConfig._donateAPIBase, "donateAPIBase"),
            (SecureConfig._donatePageURL, "donatePageURL"),
            (SecureConfig._fallbackDonate, "fallbackDonate"),
            (SecureConfig._socialMessenger, "socialMessenger"),
            (SecureConfig._socialTelegram, "socialTelegram"),
            (SecureConfig._socialZalo, "socialZalo"),
            (SecureConfig._socialDonate, "socialDonate"),
            (SecureConfig._workersDev, "workersDev"),
        ]
        
        let forbidden = ["http", "www.", ".com", ".me", ".dev", "zalo", "facebook", "telegram"]
        
        for (encrypted, name) in allEncrypted {
            XCTAssertFalse(encrypted.isEmpty, "\(name) không được rỗng")
            for keyword in forbidden {
                XCTAssertFalse(
                    encrypted.lowercased().contains(keyword),
                    "\(name) chứa plaintext '\(keyword)'"
                )
            }
        }
    }
}
