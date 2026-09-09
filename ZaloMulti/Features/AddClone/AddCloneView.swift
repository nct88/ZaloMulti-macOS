// AddCloneView.swift
// ZaloMulti
//
// Form thêm clone trong NSPanel. Ô nhập là NSTextField thật;
// nút Tạo Clone đọc trực tiếp stringValue, không phụ thuộc SwiftUI Binding.

import SwiftUI
import AppKit

@MainActor
final class AddCloneFormModel: NSObject, ObservableObject, NSTextFieldDelegate {
    @Published var isCreating = false
    @Published var createComplete = false
    @Published var errorMessage: String?
    
    let nameField = NSTextField(string: "")
    let phoneField = NSTextField(string: "")
    
    var onSubmitPhone: (() -> Void)?
    
    var trimmedName: String {
        nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    var trimmedPhone: String {
        phoneField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    override init() {
        super.init()
        configure(nameField, placeholder: "VD: Business, Shop Online...")
        configure(phoneField, placeholder: "0901234567")
        nameField.delegate = self
        phoneField.delegate = self
    }
    
    private func configure(_ field: NSTextField, placeholder: String) {
        field.placeholderString = placeholder
        field.isBordered = true
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.focusRingType = .default
        field.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        field.isEditable = true
        field.isSelectable = true
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }
    
    func setFieldsEnabled(_ enabled: Bool) {
        nameField.isEditable = enabled
        nameField.isEnabled = enabled
        phoneField.isEditable = enabled
        phoneField.isEnabled = enabled
    }
    
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            if control === phoneField {
                onSubmitPhone?()
                return true
            }
            nameField.window?.makeFirstResponder(phoneField)
            return true
        }
        return false
    }
}

struct ExistingNSTextField: NSViewRepresentable {
    let field: NSTextField
    
    func makeNSView(context: Context) -> NSTextField { field }
    func updateNSView(_ nsView: NSTextField, context: Context) {}
}

struct AddCloneView: View {
    @ObservedObject var model: AddCloneFormModel
    @ObservedObject var store: CloneStore
    @ObservedObject var engine: ZaloCloneEngine
    var onClose: () -> Void
    
    init(model: AddCloneFormModel, store: CloneStore = .shared, onClose: @escaping () -> Void) {
        self.model = model
        self.store = store
        self.engine = store.engine
        self.onClose = onClose
    }
    
    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox("Thông tin tài khoản") {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Tên hiển thị")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            ExistingNSTextField(field: model.nameField)
                                .frame(maxWidth: .infinity, minHeight: 24)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Số điện thoại")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            ExistingNSTextField(field: model.phoneField)
                                .frame(maxWidth: .infinity, minHeight: 24)
                        }
                        
                        if model.isCreating {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text(engine.progressMessage.isEmpty ? "Đang khởi tạo..." : engine.progressMessage)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                ProgressView(value: progressValue)
                                    .progressViewStyle(.linear)
                                    .tint(.accentColor)
                                Text(progressStep)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.top, 4)
                        }
                        
                        if let error = model.errorMessage {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.red)
                                Text(error)
                                    .font(.caption)
                                    .foregroundColor(.red)
                                    .lineLimit(2)
                            }
                            .padding(.top, 4)
                        }
                        
                        if model.createComplete {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("Tạo clone thành công!")
                                    .font(.caption)
                                    .foregroundColor(.green)
                                    .fontWeight(.semibold)
                            }
                            .padding(.top, 4)
                        }
                    }
                    .padding(10)
                }
            }
            .padding(16)
            
            Spacer()
            
            Divider()
            
            HStack {
                Spacer()
                Button("Huỷ", action: onClose)
                    .keyboardShortcut(.escape)
                    .disabled(model.isCreating)
                Button(model.createComplete ? "Đóng" : "Tạo Clone") {
                    if model.createComplete {
                        onClose()
                    } else {
                        createClone()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isCreating)
            }
            .padding()
        }
        .frame(width: 460, height: 280)
        .onAppear {
            model.onSubmitPhone = { createClone() }
            DispatchQueue.main.async {
                model.nameField.window?.makeFirstResponder(model.nameField)
            }
        }
    }
    
    private var progressStep: String {
        let msg = engine.progressMessage
        if msg.contains("chuẩn bị") { return "Bước 1/7 — Đang chuẩn bị..." }
        if msg.contains("thư mục") { return "Bước 1/7 — Tạo thư mục dữ liệu" }
        if msg.contains("Sao chép") { return "Bước 2/7 — Sao chép ứng dụng Zalo" }
        if msg.contains("Bundle") { return "Bước 3/7 — Đổi Bundle Identifier" }
        if msg.contains("Socket") || msg.contains("asar") { return "Bước 4/7 — Vá Socket cách ly" }
        if msg.contains("wrapper") || msg.contains("launcher") || msg.contains("môi trường") || msg.contains("cách ly") { return "Bước 5/7 — Gắn môi trường cách ly" }
        if msg.contains("quarantine") { return "Bước 6/7 — Xoá quarantine" }
        if msg.contains("sign") || msg.contains("Re-sign") { return "Bước 7/7 — Ký mã ứng dụng" }
        if msg.contains("Hoàn thành") { return "✅ Hoàn thành!" }
        return "Đang xử lý..."
    }
    
    private var progressValue: Double {
        let msg = engine.progressMessage
        if msg.contains("chuẩn bị") { return 0.05 }
        if msg.contains("thư mục") { return 1.0/7.0 }
        if msg.contains("Sao chép") { return 2.0/7.0 }
        if msg.contains("Bundle") { return 3.0/7.0 }
        if msg.contains("Socket") || msg.contains("asar") { return 4.0/7.0 }
        if msg.contains("wrapper") || msg.contains("launcher") || msg.contains("môi trường") || msg.contains("cách ly") { return 5.0/7.0 }
        if msg.contains("quarantine") { return 6.0/7.0 }
        if msg.contains("sign") || msg.contains("Re-sign") { return 6.5/7.0 }
        if msg.contains("Hoàn thành") { return 1.0 }
        return 0.02
    }
    
    private func createClone() {
        let cleanName = model.trimmedName
        guard !cleanName.isEmpty else {
            model.errorMessage = "Nhập tên hiển thị trước khi tạo clone."
            return
        }
        guard store.canAddMore else {
            model.errorMessage = "Đã đạt giới hạn tối đa \(CloneStore.maxClones) tài khoản."
            return
        }
        
        DiagnosticLogger.info("CREATE", "Form submit name='\(cleanName)' phone='\(model.trimmedPhone)'")
        model.errorMessage = nil
        model.isCreating = true
        model.setFieldsEnabled(false)
        engine.progressMessage = "Đang chuẩn bị..."
        
        Task {
            do {
                let nextIndex = (store.clones.map(\.cloneIndex).max() ?? 0) + 1
                let clone = try await store.engine.createClone(
                    index: nextIndex,
                    name: cleanName,
                    phone: model.trimmedPhone
                )
                await MainActor.run {
                    store.clones.append(clone)
                    store.saveClones()
                    model.isCreating = false
                    model.createComplete = true
                }
                try? await Task.sleep(for: .seconds(1.0))
                await MainActor.run {
                    onClose()
                }
            } catch {
                await MainActor.run {
                    model.isCreating = false
                    model.setFieldsEnabled(true)
                    model.errorMessage = error.localizedDescription
                }
                DiagnosticLogger.error("CREATE", "Lỗi tạo clone: \(error.localizedDescription)")
            }
        }
    }
}

@MainActor
final class AddCloneWindow: NSObject, NSWindowDelegate {
    static let shared = AddCloneWindow()
    
    private var panel: NSPanel?
    private var formModel: AddCloneFormModel?
    
    func present() {
        DiagnosticLogger.info("UI", "AddCloneWindow.present")
        CloneStore.shared.showAddCloneSheet = true
        
        if let panel, panel.isVisible {
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        close()
        
        let model = AddCloneFormModel()
        formModel = model
        let root = AddCloneView(model: model, onClose: { [weak self] in
            self?.close()
        })
        
        let hosting = NSHostingView(rootView: root)
        let size = NSSize(width: 480, height: 300)
        hosting.frame = NSRect(origin: .zero, size: size)
        
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Thêm tài khoản Clone"
        panel.contentView = hosting
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.delegate = self
        if let parent = NSApp.keyWindow ?? NSApp.mainWindow {
            panel.setFrameOrigin(NSPoint(
                x: parent.frame.midX - size.width / 2,
                y: parent.frame.midY - size.height / 2
            ))
        } else {
            panel.center()
        }
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.panel = panel
    }
    
    func close() {
        guard panel != nil else { return }
        DiagnosticLogger.info("UI", "AddCloneWindow.close")
        panel?.delegate = nil
        panel?.orderOut(nil)
        panel = nil
        formModel = nil
        CloneStore.shared.showAddCloneSheet = false
    }
    
    func windowWillClose(_ notification: Notification) {
        panel = nil
        formModel = nil
        CloneStore.shared.showAddCloneSheet = false
    }
}
