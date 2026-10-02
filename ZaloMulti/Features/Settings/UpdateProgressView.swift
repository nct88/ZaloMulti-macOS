import SwiftUI

struct UpdateProgressView: View {
    @ObservedObject var updater: InAppUpdater
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {

            VStack(spacing: 12) {

                ZStack {
                    Circle()
                        .fill(iconGradient)
                        .frame(width: 64, height: 64)

                    Image(systemName: iconName)
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(.white)
                        .symbolEffect(.pulse, isActive: isAnimating)
                }
                .padding(.top, 8)

                Text(titleText)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)

                Text(subtitleText)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)

            Spacer().frame(height: 24)

            if isShowingProgress {
                VStack(spacing: 8) {
                    ProgressView(value: updater.downloadProgress)
                        .progressViewStyle(.linear)
                        .tint(.blue)

                    HStack {
                        Text(updater.state.displayText)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)

                        Spacer()

                        if case .downloading = updater.state {
                            Text("\(Int(updater.downloadProgress * 100))%")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundStyle(.blue)
                        }
                    }
                }
                .padding(.horizontal, 24)
            }

            if isShowingSpinner {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text(updater.state.displayText)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 24)
            }

            Spacer().frame(height: 24)

            HStack(spacing: 12) {
                if case .available = updater.state {

                    Button("Bỏ qua") {
                        updater.dismiss()
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                    Button("Cập nhật ngay") {
                        updater.performUpdate()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                } else if case .downloading = updater.state {
                    Button("Hủy") {
                        updater.cancelUpdate()
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                } else if case .failed(let msg) = updater.state {
                    Button("Đóng") {
                        updater.dismiss()
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                    Button("Thử lại") {
                        updater.performUpdate()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                } else if case .upToDate = updater.state {
                    Button("OK") {
                        updater.dismiss()
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
        .frame(width: 380, height: 300)
        .background(.ultraThinMaterial)
    }

    private var iconName: String {
        switch updater.state {
        case .available: return "arrow.down.circle"
        case .downloading: return "arrow.down.circle"
        case .extracting: return "archivebox"
        case .installing: return "checkmark.seal"
        case .restarting: return "arrow.clockwise"
        case .failed: return "exclamationmark.triangle"
        case .upToDate: return "checkmark.circle"
        default: return "arrow.triangle.2.circlepath"
        }
    }

    private var iconGradient: LinearGradient {
        switch updater.state {
        case .failed:
            return LinearGradient(colors: [.red, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .upToDate:
            return LinearGradient(colors: [.green, .mint], startPoint: .topLeading, endPoint: .bottomTrailing)
        default:
            return LinearGradient(colors: [.blue, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    private var titleText: String {
        switch updater.state {
        case .available(let v, _): return "Có bản cập nhật v\(v)"
        case .downloading: return "Đang tải cập nhật..."
        case .extracting: return "Đang giải nén..."
        case .installing: return "Đang cài đặt..."
        case .restarting: return "Khởi động lại..."
        case .failed: return "Cập nhật thất bại"
        case .upToDate: return "Đã là bản mới nhất ✓"
        default: return "Kiểm tra cập nhật"
        }
    }

    private var subtitleText: String {
        switch updater.state {
        case .available(_, let notes): return notes
        case .downloading: return "Vui lòng không tắt ứng dụng"
        case .extracting: return "Đang xử lý file tải về..."
        case .installing: return "Đang thay thế phiên bản cũ..."
        case .restarting: return "ZaloMulti sẽ khởi động lại ngay"
        case .failed(let msg): return msg
        case .upToDate:
            let ver = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
            return "Bạn đang sử dụng v\(ver)"
        default: return "Đang kết nối máy chủ..."
        }
    }

    private var isShowingProgress: Bool {
        if case .downloading = updater.state { return true }
        return false
    }

    private var isShowingSpinner: Bool {
        switch updater.state {
        case .checking, .extracting, .installing, .restarting: return true
        default: return false
        }
    }

    private var isAnimating: Bool {
        switch updater.state {
        case .downloading, .extracting, .installing, .restarting: return true
        default: return false
        }
    }
}
