import Foundation
import AppKit

struct ZaloProfile: Sendable {
    let displayName: String?
    let avatarURL: String?
}

final class AvatarExtractor: @unchecked Sendable {

    private static let lock = NSLock()

    nonisolated(unsafe) private static let imageCache = NSCache<NSNumber, NSImage>()
    nonisolated(unsafe) private static var profileCache: [Int: ZaloProfile] = [:]

    private static let _configureOnce: Void = {
        imageCache.countLimit = 20
        imageCache.totalCostLimit = 50 * 1024 * 1024
    }()

    nonisolated static func extractProfile(cloneIndex: Int) -> ZaloProfile? {
        _ = _configureOnce

        lock.lock()
        let cached = profileCache[cloneIndex]
        lock.unlock()
        if let cached = cached { return cached }

        let cacheDir = "\(ZaloPaths.zaloDataBase)/Data/clone\(cloneIndex)/ZaloData/Partitions/zalo/Cache/Cache_Data"
        let fm = FileManager.default

        guard fm.fileExists(atPath: cacheDir),
              let files = try? fm.contentsOfDirectory(atPath: cacheDir) else {
            return nil
        }

        let avatarMarker = Data("\"avatar\":\"".utf8)
        let closingBrace = UInt8(ascii: "}")
        let openingBrace = UInt8(ascii: "{")

        for file in files where file.hasSuffix("_0") {
            let filePath = "\(cacheDir)/\(file)"

            let result: ZaloProfile? = autoreleasepool {
                guard let data = fm.contents(atPath: filePath) else { return nil }
                guard let avatarIdx = data.range(of: avatarMarker) else { return nil }

                var jsonStart = avatarIdx.lowerBound
                while jsonStart > 0 {
                    jsonStart -= 1
                    if data[jsonStart] == openingBrace { break }
                }

                var jsonEnd = avatarIdx.upperBound
                while jsonEnd < data.count - 1 {
                    if data[jsonEnd] == closingBrace {
                        if jsonEnd + 1 < data.count && data[jsonEnd + 1] == closingBrace {
                            jsonEnd += 1
                        } else {
                            break
                        }
                    }
                    jsonEnd += 1
                }

                let jsonData = data[jsonStart...jsonEnd]
                guard let jsonStr = String(data: jsonData, encoding: .utf8) else { return nil }

                var avatarURL: String?
                if let range = jsonStr.range(of: #""avatar":"(https:[^"]+)""#, options: .regularExpression) {
                    avatarURL = String(jsonStr[range])
                        .replacingOccurrences(of: "\"avatar\":\"", with: "")
                        .replacingOccurrences(of: "\"", with: "")
                        .replacingOccurrences(of: "\\/", with: "/")
                        .replacingOccurrences(of: "/120/", with: "/240/")
                }

                var displayName: String?
                if let range = jsonStr.range(of: #""display_name":"([^"]+)""#, options: .regularExpression) {
                    displayName = String(jsonStr[range])
                        .replacingOccurrences(of: "\"display_name\":\"", with: "")
                        .replacingOccurrences(of: "\"", with: "")
                }

                if avatarURL != nil || displayName != nil {
                    return ZaloProfile(displayName: displayName, avatarURL: avatarURL)
                }
                return nil
            }

            if let profile = result {
                lock.lock()
                profileCache[cloneIndex] = profile
                lock.unlock()
                return profile
            }
        }

        return nil
    }

    nonisolated static func extractAvatarURL(cloneIndex: Int) -> String? {
        return extractProfile(cloneIndex: cloneIndex)?.avatarURL
    }

    nonisolated static func extractDisplayName(cloneIndex: Int) -> String? {
        return extractProfile(cloneIndex: cloneIndex)?.displayName
    }

    static func loadAvatar(cloneIndex: Int, completion: @escaping (NSImage?) -> Void) {
        _ = _configureOnce
        let key = NSNumber(value: cloneIndex)

        if let cached = imageCache.object(forKey: key) {
            completion(cached)
            return
        }

        let cachePath = "\(ZaloPaths.zaloDataBase)/Data/clone\(cloneIndex)/avatar_cache.jpg"
        if FileManager.default.fileExists(atPath: cachePath),
           let image = NSImage(contentsOfFile: cachePath) {
            imageCache.setObject(image, forKey: key, cost: estimateImageCost(image))
            completion(image)
            return
        }

        guard let urlStr = extractAvatarURL(cloneIndex: cloneIndex),
              let url = URL(string: urlStr) else {
            completion(nil)
            return
        }

        URLSession.shared.dataTask(with: url) { data, response, error in
            guard let data = data, error == nil, let image = NSImage(data: data) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            try? data.write(to: URL(fileURLWithPath: cachePath))

            imageCache.setObject(image, forKey: key, cost: estimateImageCost(image))

            DispatchQueue.main.async { completion(image) }
        }.resume()
    }

    static func loadProfile(cloneIndex: Int, completion: @escaping (ZaloProfile?, NSImage?) -> Void) {
        let profile = extractProfile(cloneIndex: cloneIndex)
        loadAvatar(cloneIndex: cloneIndex) { image in
            completion(profile, image)
        }
    }

    static func clearCache(cloneIndex: Int) {
        let key = NSNumber(value: cloneIndex)
        imageCache.removeObject(forKey: key)

        lock.lock()
        profileCache.removeValue(forKey: cloneIndex)
        lock.unlock()

        let cachePath = "\(ZaloPaths.zaloDataBase)/Data/clone\(cloneIndex)/avatar_cache.jpg"
        try? FileManager.default.removeItem(atPath: cachePath)
    }

    static func clearAllCache() {
        imageCache.removeAllObjects()
        lock.lock()
        profileCache.removeAll()
        lock.unlock()
    }

    private static func estimateImageCost(_ image: NSImage) -> Int {
        guard let rep = image.representations.first else { return 100_000 }
        return rep.pixelsWide * rep.pixelsHigh * 4
    }
}
