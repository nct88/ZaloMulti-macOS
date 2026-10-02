import SwiftUI

struct PrivateNotificationListView: View {
    @ObservedObject var monitor = NotificationMonitor.shared

    var body: some View {
        VStack(spacing: 0) {

            HStack(spacing: 6) {
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .symbolEffect(.pulse, isActive: monitor.unreadCount > 0)

                Text("THÔNG BÁO")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .tracking(0.5)

                Spacer()

                if monitor.unreadCount > 0 {
                    Text("\(monitor.unreadCount)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red)
                        .clipShape(Capsule())
                        .transition(.scale.combined(with: .opacity))
                }

                Menu {
                    Button(action: { monitor.markAllAsRead() }) {
                        Label("Đánh dấu tất cả đã đọc", systemImage: "checkmark.circle")
                    }
                    Divider()
                    Button(role: .destructive, action: { monitor.clearAll() }) {
                        Label("Xóa tất cả", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .menuStyle(.borderlessButton)
                .frame(width: 20)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            if monitor.notifications.isEmpty {

                VStack(spacing: 10) {
                    Spacer()

                    Image(systemName: "bell.slash")
                        .font(.system(size: 28))
                        .foregroundStyle(.quaternary)

                    Text("Chưa có thông báo")
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)

                    Text("Tin nhắn từ các tài khoản\nsẽ hiển thị tại đây")
                        .font(.system(size: 11))
                        .foregroundStyle(.quaternary)
                        .multilineTextAlignment(.center)

                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(monitor.notifications) { notification in
                            NotificationRowView(notification: notification)
                                .environmentObject(monitor)

                            Divider()
                                .padding(.leading, 50)
                        }
                    }
                }
            }
        }
    }
}

struct NotificationRowView: View {
    let notification: PrivateNotification
    @ObservedObject var monitor = NotificationMonitor.shared
    @State private var isHovered = false
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            HStack(alignment: .top, spacing: 10) {

                ZStack {
                    Circle()
                        .fill(Color(hex: notification.avatarColor))
                        .frame(width: 32, height: 32)

                    Text(String(notification.title.prefix(1)).uppercased())
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(notification.title)
                            .font(.system(size: 12, weight: notification.isRead ? .medium : .bold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Spacer()

                        Text(notification.timeAgo)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }

                    Text(notification.body)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(isExpanded ? nil : 2)

                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color(hex: notification.avatarColor))
                            .frame(width: 5, height: 5)
                        Text(notification.cloneName)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.tertiary)

                        Spacer()

                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 8))
                            .foregroundStyle(.quaternary)
                    }
                }

                if !notification.isRead {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 7, height: 7)
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    Divider()

                    Text(notification.body)
                        .font(.system(size: 12))
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .padding(.horizontal, 12)

                    HStack(spacing: 12) {
                        Label(notification.cloneName, systemImage: "person.circle")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)

                        Label(notification.formattedTimestamp, systemImage: "clock")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)

                    HStack(spacing: 8) {
                        Button {
                            monitor.markAsRead(notification)
                        } label: {
                            Label("Đã đọc", systemImage: "checkmark.circle")
                                .font(.system(size: 10))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .disabled(notification.isRead)

                        Button(role: .destructive) {
                            withAnimation {
                                monitor.removeNotification(notification)
                            }
                        } label: {
                            Label("Xóa", systemImage: "trash")
                                .font(.system(size: 10))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .tint(.red)

                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                }
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            notification.isRead
                ? (isHovered ? Color.primary.opacity(0.03) : Color.clear)
                : (isHovered ? Color.accentColor.opacity(0.08) : Color.accentColor.opacity(0.04))
        )
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
                if !notification.isRead {
                    monitor.markAsRead(notification)
                }
            }
        }
        .contextMenu {
            Button(action: {
                withAnimation { isExpanded.toggle() }
            }) {
                Label(isExpanded ? "Thu gọn" : "Xem chi tiết", systemImage: isExpanded ? "rectangle.compress.vertical" : "rectangle.expand.vertical")
            }
            Button(action: { monitor.markAsRead(notification) }) {
                Label("Đánh dấu đã đọc", systemImage: "checkmark.circle")
            }
            Divider()
            Button(role: .destructive, action: {
                withAnimation { monitor.removeNotification(notification) }
            }) {
                Label("Xóa thông báo", systemImage: "trash")
            }
        }
    }
}
