import SwiftUI

@MainActor
final class AddCloneFormState: ObservableObject {
    @Published var name = ""
    @Published var phone = ""
    @Published var isCreating = false
    @Published var errorMessage: String?

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedPhone: String {
        phone.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct AddCloneView: View {
    @ObservedObject var store: CloneStore
    @ObservedObject var engine: ZaloCloneEngine
    @StateObject private var form = AddCloneFormState()

    private enum Field { case name, phone }
    @FocusState private var focusedField: Field?

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
                            TextField("VD: Business, Shop Online...", text: $form.name)
                                .textFieldStyle(.roundedBorder)
                                .focused($focusedField, equals: .name)
                                .disabled(form.isCreating)
                                .onSubmit { focusedField = .phone }
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Số điện thoại")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField("0901234567", text: $form.phone)
                                .textFieldStyle(.roundedBorder)
                                .focused($focusedField, equals: .phone)
                                .disabled(form.isCreating)
                                .onSubmit { createClone() }
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
                    DiagnosticLogger.info("UI", "AddClone: bấm Huỷ isCreating=\(form.isCreating)")
                    guard !form.isCreating else { return }
                    store.showAddCloneSheet = false
                }
                .keyboardShortcut(.escape)
                .disabled(form.isCreating)

                Button("Tạo Clone") {
                    DiagnosticLogger.info("UI", "AddClone: bấm Tạo Clone")
                    createClone()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
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
            DiagnosticLogger.info("UI", "AddCloneView onAppear")

            DispatchQueue.main.async { focusedField = .name }
        }
        .onChange(of: focusedField) { _, newValue in
            DiagnosticLogger.info("UI", "AddCloneView focusedField=\(String(describing: newValue))")
            if let w = NSApp.keyWindow {
                DiagnosticLogger.info("UI", "keyWindow=\(type(of: w)) '\(w.title)' firstResponder=\(w.firstResponder.map { String(describing: type(of: $0)) } ?? "nil")")
            } else {
                DiagnosticLogger.info("UI", "keyWindow=nil")
            }
        }
        .onChange(of: form.name) { _, v in
            DiagnosticLogger.info("UI", "form.name → '\(v)'")
        }
        .onChange(of: form.phone) { _, v in
            DiagnosticLogger.info("UI", "form.phone → '\(v)'")
        }
        .onDisappear {
            DiagnosticLogger.info("UI", "AddCloneView onDisappear")
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
        focusedField = nil
        let name = form.trimmedName
        DiagnosticLogger.info("CREATE", "createClone nameLen=\(name.count) canAddMore=\(store.canAddMore) engineBusy=\(store.engine.isProcessing)")
        guard !name.isEmpty else {
            form.errorMessage = "Nhập tên hiển thị trước khi tạo clone."
            focusedField = .name
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
                form.errorMessage = error.localizedDescription
            }
        }
    }
}
