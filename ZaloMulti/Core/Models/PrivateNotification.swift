import Foundation

struct PrivateNotification: Identifiable, Equatable {
    let id = UUID()
    let cloneId: UUID?
    let cloneName: String
    let avatarColor: String
    let title: String
    let body: String
    let timestamp: Date
    var isRead: Bool = false

    var timeAgo: String {
        let interval = Date().timeIntervalSince(timestamp)
        if interval < 60 { return "vừa xong" }
        if interval < 3600 { return "\(Int(interval / 60)) phút" }
        if interval < 86400 { return "\(Int(interval / 3600)) giờ" }
        return "\(Int(interval / 86400)) ngày"
    }

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm · dd/MM"
        return f
    }()

    var formattedTimestamp: String {
        Self.timestampFormatter.string(from: timestamp)
    }
}
