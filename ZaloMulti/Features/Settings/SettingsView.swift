import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("Chung", systemImage: "gear")
                }

            LogSettingsView()
                .tabItem {
                    Label("Log", systemImage: "doc.text.magnifyingglass")
                }

            AboutView()
                .tabItem {
                    Label("Giới thiệu", systemImage: "info.circle")
                }
        }
        .frame(width: 560, height: 400)
    }
}

struct LogSettingsView: View {
    @State private var logContent = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Diagnostic Log")
                    .font(.headline)
                Spacer()

                Button("Xuất log ra Desktop") {
                    DiagnosticTracer.exportReport(store: CloneStore.shared)
                }
                .buttonStyle(.bordered)

                Button("Mở trong Finder") {
                    DiagnosticLogger.openLogInFinder()
                }
                .buttonStyle(.bordered)

                Button("Copy đường dẫn") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(DiagnosticLogger.logFilePath, forType: .string)
                }
                .buttonStyle(.bordered)

                Button("Refresh") {
                    loadLog()
                }
                .buttonStyle(.borderedProminent)
            }

            Text("File: \(DiagnosticLogger.logFilePath)")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            ScrollView {
                Text(logContent)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: .infinity)
            .padding(8)
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )
        }
        .padding()
        .onAppear { loadLog() }
    }

    private func loadLog() {
        let full = DiagnosticLogger.readLogContents()
        let lines = full.components(separatedBy: "\n")
        let tail = lines.suffix(200)
        logContent = tail.joined(separator: "\n")
    }
}

struct GeneralSettingsView: View {
    @StateObject private var settings = SettingsManager.shared

    var body: some View {
        Form {
            Section("Giao diện") {
                Picker("Chủ đề", selection: $settings.settings.theme) {
                    Text("Theo hệ thống").tag("system")
                    Text("Sáng").tag("light")
                    Text("Tối").tag("dark")
                }
            }

            Section("Chung") {
                Toggle("Hiện icon trên Menu Bar", isOn: $settings.settings.showMenuBarIcon)
                Toggle("Kiểm tra cập nhật khi khởi động", isOn: $settings.settings.checkUpdateOnStartup)

                Stepper("Giới hạn số clone: \(settings.settings.maxClones)",
                        value: $settings.settings.maxClones, in: 1...50)
            }
        }
        .padding()
    }
}

struct AboutView: View {
    var body: some View {
        VStack(spacing: 16) {
            RoundedRectangle(cornerRadius: 12)
                .fill(LinearGradient(
                    colors: [.zaloPrimary, .zaloDark],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
                .frame(width: 64, height: 64)
                .overlay(
                    Text("Z")
                        .font(.system(size: 28, weight: .heavy))
                        .foregroundColor(.white)
                )

            Text("ZaloMulti")
                .font(.title3)
                .fontWeight(.bold)

            Text("Phiên bản \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.0") (macOS)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()
                .frame(width: 200)

            Text("Quản lý đa tài khoản Zalo Clone")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("© 2026 ZaloMulti — All rights reserved")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding()
    }
}
