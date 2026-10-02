import Foundation
import CryptoKit

enum SecureConfig {

    nonisolated(unsafe) private static var _cachedKey: SymmetricKey?

    private static func _saltMix() -> Data {
        let a: [UInt8] = [0x9e, 0x42, 0x17, 0xC5, 0x6B, 0x30, 0xFA, 0x8D]
        let b: [UInt8] = [0x24, 0xBE, 0x71, 0x0F, 0x53, 0xA9, 0xE6, 0x1C]
        let c: [UInt8] = [0xD7, 0x38, 0x92, 0x4E, 0xB0, 0x6F, 0x15, 0xCA]
        let d: [UInt8] = [0x83, 0x5D, 0xE1, 0x2A, 0x74, 0xC8, 0x39, 0x9F]
        var out = [UInt8](repeating: 0, count: 32)
        for i in 0..<8 {
            out[i]      = a[i] ^ 0x5A
            out[i + 8]  = (b[i] &+ UInt8(truncatingIfNeeded: i &* 11)) ^ 0x33
            out[i + 16] = c[i] ^ (d[i] &>> 1)
            out[i + 24] = (d[i] &+ a[i]) ^ 0xC7
        }
        return Data(out)
    }

    private static var decryptionKey: SymmetricKey {
        if let cached = _cachedKey { return cached }
        let bid = Data((Bundle.main.bundleIdentifier ?? "").utf8)
        var h1 = SHA256()
        h1.update(data: Data("zmc.v2.kdf".utf8))
        h1.update(data: bid)
        h1.update(data: _saltMix())
        h1.update(data: Data(bid.reversed()))
        let r1 = Data(h1.finalize())
        var h2 = SHA256()
        h2.update(data: r1)
        h2.update(data: _saltMix())
        let key = SymmetricKey(data: h2.finalize())
        _cachedKey = key
        return key
    }

    static let _donateAPIBase = "b6cbbb14fff795bda269f915f784c63abd83335accb68f744dd536bcae62676f9c956c7e124d77ca309a2409cb8e8c312f"
    static let _donatePageURL = "d7235a6cd7adff8972920f843a88e449a82da7447a867966da3483d80a74b55b8bf4bb688f8eab8312a8c3add309c34710d099f0"
    static let _fallbackDonate = "b826ca1aa9f7203dff3e13fd64fb66b2bf112ee9faac399449c049fe9169f9f5943f4c55a3a80e42ba2630e97311a0f759b918dc"
    static let _githubRepoPath = "9e7a14ac881d754eec23cafbef9f07ed72c2ebc12d0290d9138be9650f125b38ad5ba3d87d3e14a0b11f0670ca809c1409"
    static let _githubAPIBase = "b85e99c592fa7f24259d807b332edca16a075aa1647db111bcd8d14feac0dfc82ed5bbd513b90e537f4e39bd89a8c9c355a709a802daf5c86d"
    static let _socialMessenger = "bf312f645fb279a336eef45d6a31854dd98524a7468df61f37f3d5f0461c3daff298c8b454c0ed54f207a60ad49b22f251850f7ca9"
    static let _socialTelegram = "cee17d5f54a42fbb2b3666f9e2068f1930067272903b702ab59063d2053de6888df0d1dc2ab6dd80a4cf25e5df0bead8d18c3c82fc"
    static let _socialZalo = "926126c908b60f766f026a3a4609119c07fcb1970e660e263cd55661c96d8f073d4252742f16ed007832ff039bda52a41aecbedad77c2828"
    static let _socialDonate = "302ad2b3e0efa6ff9eefea4efb5a7e769a496a7dc43c505dc74e3d002ec0a07e9b6051921062fb47af98ceb5d82d0f43d6affbd9"
    static let _logSubsystem = "02082c9c89751f069c0b9384187bb7639711a479966088d01a7793450e8af343ca677ca632f09d9c788553fff65a125dadf624792b9e"
    static let _workersDev = "8a8d49c228a7e5223edf8107f85da8e6bf9e1496f2945c601389c82a8610d97fdfc95ef906424f"
    static let _integrityDonate = "e60c9f412b3e5e49fe4516d9819273e0f21a880ea503f401bcd0c21d6438c95be9f7"
    static let _contactEmail = "974f05148c087083aab6dbad3124a6de411d5d2e93fa5ceaf5cbcfcb38dab10df59d02382f54a00f3014bccc"
    static let _contactPhone = "a4ed5b2b8936a0968cc6ee35f132d5a5a383ee3d407b356b8174d3728d1663cdf44bae0f894a"

    static var donateAPIBase: String { decrypt(_donateAPIBase) ?? "" }
    static var donatePageURL: String { decrypt(_donatePageURL) ?? "" }
    static var fallbackDonate: String { decrypt(_fallbackDonate) ?? "" }
    static var githubRepoPath: String { decrypt(_githubRepoPath) ?? "" }
    static var githubAPIURL: String {
        let base = decrypt(_githubAPIBase) ?? ""
        let repo = decrypt(_githubRepoPath) ?? ""
        return "\(base)\(repo)/releases/latest"
    }
    static var socialMessenger: String { decrypt(_socialMessenger) ?? "" }
    static var socialTelegram: String { decrypt(_socialTelegram) ?? "" }
    static var socialZalo: String { decrypt(_socialZalo) ?? "" }
    static var socialDonate: String { decrypt(_socialDonate) ?? "" }
    static var logSubsystem: String { decrypt(_logSubsystem) ?? "" }

    static var contactEmail: String { decrypt(_contactEmail) ?? "" }
    static var contactPhone: String { decrypt(_contactPhone) ?? "" }

    static var workersDev: String { decrypt(_workersDev) ?? "" }
    static var integrityDonate: String { decrypt(_integrityDonate) ?? "" }

    static func decrypt(_ hexString: String) -> String? {
        guard let combined = Data(hexString: hexString),
              combined.count > 28 else { return nil }

        let nonceData = combined.prefix(12)
        let ciphertext = combined[combined.index(combined.startIndex, offsetBy: 12)..<combined.index(combined.endIndex, offsetBy: -16)]
        let tag = combined.suffix(16)

        do {
            let sealedBox = try AES.GCM.SealedBox(
                nonce: .init(data: nonceData),
                ciphertext: ciphertext,
                tag: tag
            )
            let plainData = try AES.GCM.open(sealedBox, using: decryptionKey)
            return String(data: plainData, encoding: .utf8)
        } catch {
            return nil
        }
    }
}

extension Data {
    init?(hexString: String) {
        let hex = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard hex.count % 2 == 0 else { return nil }
        var data = Data(capacity: hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let nextIndex = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<nextIndex], radix: 16) else { return nil }
            data.append(byte)
            index = nextIndex
        }
        self = data
    }
}
