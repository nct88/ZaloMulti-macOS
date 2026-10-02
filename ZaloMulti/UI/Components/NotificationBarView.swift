import SwiftUI

struct NotificationBarView: View {

    private var zaloInfo: (installed: Bool, version: String?, bundleID: String?) {
        let fm = FileManager.default
        let path = "/Applications/Zalo.app"
        guard fm.fileExists(atPath: path) else {
            return (false, nil, nil)
        }
        let plistPath = "\(path)/Contents/Info.plist"
        if let plist = NSDictionary(contentsOfFile: plistPath) {
            let version = plist["CFBundleShortVersionString"] as? String
            let bundleID = plist["CFBundleIdentifier"] as? String
            return (true, version, bundleID)
        }
        return (true, nil, nil)
    }

    var body: some View {
        let installed = zaloInfo.installed
        let version = zaloInfo.version

        HStack(spacing: 12) {

            ZStack {
                Circle()
                    .fill(installed ? Color.green : Color.orange)
                    .frame(width: 28, height: 28)

                Image(systemName: installed ? "checkmark" : "exclamationmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(installed ? "Zalo Desktop đã sẵn sàng" : "Chưa cài Zalo Desktop")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)

                Text(installed
                     ? "Phiên bản \(version ?? "N/A") — Sẵn sàng tạo clone"
                     : "Cài Zalo từ zalo.me/pc để bắt đầu")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let version = version {
                Text("v\(version)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(installed ? .green : .orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(
                        (installed ? Color.green : Color.orange)
                            .opacity(0.12)
                    )
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(installed
                      ? Color.green.opacity(0.08)
                      : Color.orange.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(
                            installed
                            ? Color.green.opacity(0.2)
                            : Color.orange.opacity(0.2),
                            lineWidth: 1
                        )
                )
        )
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }
}
