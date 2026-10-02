// NotificationMonitor.swift
// ZaloMulti
//
// Theo dõi và chặn thông báo từ các Zalo clone processes.
// Chuyển thông báo vào sidebar để bảo vệ quyền riêng tư.
//
// ⚡ Performance: Dùng DispatchSource (kqueue) thay vì polling filesystem.
//    kqueue là kernel-level event → zero CPU khi idle, instant notification.

@preconcurrency import Foundation
import AppKit
import SwiftUI

/// Monitor theo dõi macOS notifications từ Zalo clones
@MainActor
final class NotificationMonitor: ObservableObject {
    static let shared = NotificationMonitor()
    @Published var notifications: [PrivateNotification] = []
    @Published var unreadCount: Int = 0
    
    /// File system watchers (kqueue-based)
    private var watchers: [Int: DispatchSourceFileSystemObject] = [:]
    private var watcherFDs: [Int: Int32] = [:]
    
    /// Fallback polling cho directories chưa tồn tại
    private var fallbackTimer: Timer?
    
    /// Debounce: tránh fire quá nhiều khi Zalo ghi nhiều files
    private var lastNotifTime: [Int: Date] = [:]
    private let debounceInterval: TimeInterval = 5.0
    
    private let maxNotifications = 100
    
    init() {
        DiagnosticLogger.info("NOTIF", "NotificationMonitor khởi tạo")
        setupWatchers()
    }
    
    // Cleanup: DispatchSource cancel handlers close file descriptors automatically
    // Timer invalidated by ARC releasing the weak reference
    
    // MARK: - Public API
    
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
    
    // MARK: - DispatchSource File Watching (kqueue)
    
    /// Setup kqueue watchers cho mỗi clone data directory
    private func setupWatchers() {
        let basePath = "\(NSHomeDirectory())/Library/Application Support/ZaloMulti/Data"
        let fm = FileManager.default
        
        guard fm.fileExists(atPath: basePath),
              let cloneDirs = try? fm.contentsOfDirectory(atPath: basePath) else {
            // Directory chưa tồn tại → fallback polling chậm (30s) để chờ tạo
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
        
        // Fallback timer để bắt clone mới được tạo
        startFallbackTimer()
        
        DiagnosticLogger.info("NOTIF", "Setup \(watchedCount) kqueue watchers")
    }
    
    /// Watch 1 directory bằng kqueue DispatchSource — zero CPU khi idle
    private func watchDirectory(path: String, cloneIndex: Int) {
        // Skip nếu đã watch
        guard watchers[cloneIndex] == nil else { return }
        
        let fd = open(path, O_EVTONLY | O_CLOEXEC)
        guard fd >= 0 else { return }
        
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .rename],
            queue: DispatchQueue.global(qos: .utility)
        )
        
        // @Sendable: handler chạy trên queue utility. Không có nó, Swift 6 coi closure
        // là @MainActor (tạo trong class @MainActor) và trap khi kqueue báo sự kiện.
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
    
    /// Handle file change event — debounced
    private func handleFileChange(cloneIndex: Int) {
        let now = Date()
        
        // Debounce: bỏ qua nếu đã fire gần đây
        if let last = lastNotifTime[cloneIndex],
           now.timeIntervalSince(last) < debounceInterval {
            return
        }
        lastNotifTime[cloneIndex] = now
        
        // Trích xuất profile info
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
    
    /// Fallback timer — scan mỗi 30s cho clone mới (thay vì 3s polling cũ)
    private func startFallbackTimer() {
        fallbackTimer?.invalidate()
        fallbackTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.setupWatchers()
            }
        }
    }
    
    // MARK: - Add Notification
    
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
        
        // Giới hạn số lượng
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
