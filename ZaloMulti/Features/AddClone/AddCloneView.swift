// AddCloneView.swift
// ZaloMulti
//
// Form thêm clone trong cùng cửa sổ SwiftUI (không NSWindow riêng).

import SwiftUI
import AppKit

@MainActor
final class AddCloneFormState: NSObject, ObservableObject, NSTextFieldDelegate {
    @Published var isCreating = false
    @Published var errorMessage: String?
    
    let nameField = NSTextField(string: "")
    let phoneField = NSTextField(string: "")
    
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
        field.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }
    
    func setEnabled(_ enabled: Bool) {
        nameField.isEnabled = enabled
        phoneField.isEnabled = enabled
        nameField.isEditable = enabled
        phoneField.isEditable = enabled
    }
    
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            if control === nameField {
                nameField.window?.makeFirstResponder(phoneField)
            }
            return true
        }
        return false
    }
}

private struct HostedTextField: NSViewRepresentable {
    let field: NSTextField
    func makeNSView(context: Context) -> NSTextField { field }
    func updateNSView(_ nsView: NSTextField, context: Context) {}
}

struct AddCloneView: View {
    @ObservedObject var store: CloneStore
    @ObservedObject var engine: ZaloCloneEngine
    @StateObject private var form = AddCloneFormState()
    
    init(store: CloneStore) {
        self.store = store
        self.engine = store.engine
    }
    
    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                GroupBox("Thông tin tài khoản") {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Tên hiển thị")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HostedTextField(field: form.nameField)
                                .frame(maxWidth: .infinity, minHeight: 24)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Số điện thoại")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HostedTextField(field: form.phoneField)
                                .frame(maxWidth: .infinity, minHeight: 24)
                        }
                        
                        if form.isCreating {
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
                            }
                        }
                        
                        if let error = form.errorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(10)
                }
            }
            .padding(16)
            
            Spacer(minLength: 0)
            
            Divider()
            
            HStack {
                Spacer()
                Button("Huỷ") {
                    guard !form.isCreating else { return }
                    store.showAddCloneSheet = false
                }
                .keyboardShortcut(.escape)
                .disabled(form.isCreating)
                
                Button("Tạo Clone") {
                    createClone()
                }
                .buttonStyle(.borderedProminent)
                .disabled(form.isCreating)
            }
            .padding()
        }
        .frame(width: 440, height: 280)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
        .onAppear {
            DispatchQueue.main.async {
                form.nameField.window?.makeFirstResponder(form.nameField)
            }
        }
    }
    
    private var progressValue: Double {
        let msg = engine.progressMessage
        if msg.contains("chuẩn bị") { return 0.08 }
        if msg.contains("thư mục") { return 0.15 }
        if msg.contains("Sao chép") { return 0.35 }
        if msg.contains("Bundle") { return 0.5 }
        if msg.contains("Socket") || msg.contains("asar") { return 0.65 }
        if msg.contains("môi trường") { return 0.75 }
        if msg.contains("quarantine") { return 0.85 }
        if msg.contains("sign") || msg.contains("Re-sign") { return 0.93 }
        if msg.contains("Hoàn thành") { return 1 }
        return 0.05
    }
    
    private func createClone() {
        if form.isCreating { return }
        let name = form.trimmedName
        guard !name.isEmpty else {
            form.errorMessage = "Nhập tên hiển thị trước khi tạo clone."
            return
        }
        guard store.canAddMore else {
            form.errorMessage = "Đã đạt giới hạn tối đa \(CloneStore.maxClones) tài khoản."
            return
        }
        guard !store.engine.isProcessing else {
            form.errorMessage = "Đang tạo clone — vui lòng chờ."
            return
        }
        
        DiagnosticLogger.info("CREATE", "Form submit name='\(name)' phone='\(form.trimmedPhone)'")
        form.isCreating = true
        form.errorMessage = nil
        form.setEnabled(false)
        
        Task { @MainActor in
            do {
                let nextIndex = (store.clones.map(\.cloneIndex).max() ?? 0) + 1
                let clone = try await store.engine.createClone(
                    index: nextIndex,
                    name: name,
                    phone: form.trimmedPhone
                )
                store.addCreatedClone(clone)
                store.showAddCloneSheet = false
            } catch {
                DiagnosticLogger.error("CREATE", "Lỗi tạo clone: \(error.localizedDescription)")
                form.isCreating = false
                form.setEnabled(true)
                form.errorMessage = error.localizedDescription
            }
        }
    }
}
