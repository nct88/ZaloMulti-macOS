@preconcurrency import Foundation
import AppKit
import SwiftUI

@MainActor
final class NotificationMonitor: ObservableObject {
    static let shared = NotificationMonitor()
    @Published var notifications: [PrivateNotification] = []
    @Published var unreadCount: Int = 0

    private var watchers: [Int: DispatchSourceFileSystemObject] = [:]
    private var watcherFDs: [Int: Int32] = [:]

    private var fallbackTimer: Timer?

    private var lastNotifTime: [Int: Date] = [:]
    private let debounceInterval: TimeInterval = 5.0

    private let maxNotifications = 100

    init() {
        DiagnosticLogger.info("NOTIF", "NotificationMonitor khởi tạo")
        setupWatchers()
    }

    func markAsRead(_ notification: PrivateNotification) {
        if let index = notifications.firstIndex(where: { $0.id == notification.id }) {
            notifications[index].isRead = true
            updateUnreadCount()
        }
    }

    func markAllAsRead() {
        for i in notifications.indices {
            notifications[i].isRead = true
        }
        updateUnreadCount()
    }

    func removeNotification(_ notification: PrivateNotification) {
        notifications.removeAll { $0.id == notification.id }
        updateUnreadCount()
    }

    func clearAll() {
        notifications.removeAll()
        unreadCount = 0
    }

    private func setupWatchers() {
        let basePath = "\(NSHomeDirectory())/Library/Application Support/ZaloMulti/Data"
        let fm = FileManager.default

        guard fm.fileExists(atPath: basePath),
              let cloneDirs = try? fm.contentsOfDirectory(atPath: basePath) else {

            startFallbackTimer()
            return
        }

        var watchedCount = 0
        for dir in cloneDirs where dir.hasPrefix("clone") {
            let cloneIndex = Int(dir.replacingOccurrences(of: "clone", with: "")) ?? 0
            let watchPath = "\(basePath)/\(dir)/ZaloData/Partitions/zalo/Local Storage/leveldb"

            guard fm.fileExists(atPath: watchPath) else { continue }
            watchDirectory(path: watchPath, cloneIndex: cloneIndex)
            watchedCount += 1
        }

        startFallbackTimer()

        DiagnosticLogger.info("NOTIF", "Setup \(watchedCount) kqueue watchers")
    }

    private func watchDirectory(path: String, cloneIndex: Int) {

        guard watchers[cloneIndex] == nil else { return }

        let fd = open(path, O_EVTONLY | O_CLOEXEC)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .rename],
            queue: DispatchQueue.global(qos: .utility)
        )

        source.setEventHandler { @Sendable [weak self] in
            Task { @MainActor [weak self] in
                self?.handleFileChange(cloneIndex: cloneIndex)
            }
        }

        source.setCancelHandler {
            close(fd)
        }

        source.resume()
        watchers[cloneIndex] = source
        watcherFDs[cloneIndex] = fd
    }

    private func handleFileChange(cloneIndex: Int) {
        let now = Date()

        if let last = lastNotifTime[cloneIndex],
           now.timeIntervalSince(last) < debounceInterval {
            return
        }
        lastNotifTime[cloneIndex] = now

        let profile = AvatarExtractor.extractProfile(cloneIndex: cloneIndex)
        let cloneName = profile?.displayName ?? "Clone \(cloneIndex)"
        let avatarColor = CloneAccount.colorForIndex(cloneIndex)

        addNotification(
            cloneId: nil,
            cloneName: cloneName,
            avatarColor: avatarColor,
            title: "Hoạt động mới",
            body: "Có tin nhắn hoặc hoạt động mới từ \(cloneName)"
        )
    }

    private func startFallbackTimer() {
        fallbackTimer?.invalidate()
        fallbackTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.setupWatchers()
            }
        }
    }

    func addFromClone(_ clone: CloneAccount, title: String, body: String) {
        addNotification(
            cloneId: clone.id,
            cloneName: clone.name,
            avatarColor: clone.avatarColor,
            title: title,
            body: body
        )
    }

    private func addNotification(
        cloneId: UUID?,
        cloneName: String,
        avatarColor: String,
        title: String,
        body: String
    ) {
        let notification = PrivateNotification(
            cloneId: cloneId,
            cloneName: cloneName,
            avatarColor: avatarColor,
            title: title,
            body: body.isEmpty ? "Tin nhắn mới" : body,
            timestamp: Date()
        )

        withAnimation(.easeInOut(duration: 0.2)) {
            notifications.insert(notification, at: 0)
        }

        if notifications.count > maxNotifications {
            notifications = Array(notifications.prefix(maxNotifications))
        }

        updateUnreadCount()
        DiagnosticLogger.info("NOTIF", "[\(cloneName)] \(title): \(body.prefix(50))")
    }

    private func updateUnreadCount() {
        unreadCount = notifications.filter { !$0.isRead }.count
    }
}
