import Foundation

enum CloneStatus: String, Codable, CaseIterable {
    case running  = "running"
    case stopped  = "stopped"
    case paused   = "paused"
    case creating = "creating"

    var displayName: String {
        switch self {
        case .running:  return "Đang chạy"
        case .stopped:  return "Đã dừng"
        case .paused:   return "Tạm dừng"
        case .creating: return "Đang tạo..."
        }
    }

    var iconName: String {
        switch self {
        case .running:  return "play.circle.fill"
        case .stopped:  return "stop.circle.fill"
        case .paused:   return "pause.circle.fill"
        case .creating: return "gear.circle.fill"
        }
    }
}

struct CloneAccount: Identifiable, Codable, Equatable {
    var id: UUID = UUID()

    var name: String
    var phoneNumber: String = ""

    var cloneIndex: Int
    var bundleID: String
    var appPath: String
    var dataPath: String

    var status: CloneStatus = .stopped
    var processID: Int32?

    var avatarColor: String

    var createdAt: Date = Date()
    var lastOpenedAt: Date?

    var deviceId: String?
    var deviceName: String?

    static func == (lhs: CloneAccount, rhs: CloneAccount) -> Bool {
        lhs.id == rhs.id &&
        lhs.status == rhs.status &&
        lhs.processID == rhs.processID &&
        lhs.name == rhs.name &&
        lhs.phoneNumber == rhs.phoneNumber
    }
}

extension CloneAccount {
    static let avatarColors: [String] = [
        "#007AFF", "#30D158", "#FF6B35", "#BF5AF2", "#FF3B30",
        "#5AC8FA", "#FF9500", "#AC8E68", "#64D2FF", "#FF2D55",
    ]

    static func colorForIndex(_ index: Int) -> String {
        avatarColors[index % avatarColors.count]
    }
}
