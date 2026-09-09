// AddCloneView.swift
// ZaloMulti
//
// Form thêm clone — cửa sổ AppKit thuần (không SwiftUI) để hiện tiến trình và lỗi.

import AppKit

@MainActor
final class AddCloneWindow: NSObject, NSWindowDelegate, NSTextFieldDelegate {
    static let shared = AddCloneWindow()
    
    private var window: NSWindow?
    private var nameField: NSTextField?
    private var phoneField: NSTextField?
    private var statusLabel: NSTextField?
    private var errorLabel: NSTextField?
    private var spinner: NSProgressIndicator?
    private var cancelButton: NSButton?
    private var createButton: NSButton?
    private var isCreating = false
    
    func present() {
        DiagnosticLogger.info("UI", "AddCloneWindow.present")
        CloneStore.shared.showAddCloneSheet = true
        
        if let window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        close()
        buildWindow()
    }
    
    func close() {
        window?.delegate = nil
        window?.orderOut(nil)
        window = nil
        nameField = nil
        phoneField = nil
        statusLabel = nil
        errorLabel = nil
        spinner = nil
        cancelButton = nil
        createButton = nil
        isCreating = false
        CloneStore.shared.showAddCloneSheet = false
    }
    
    func windowWillClose(_ notification: Notification) {
        window = nil
        isCreating = false
        CloneStore.shared.showAddCloneSheet = false
    }
    
    // MARK: - Layout
    
    private func buildWindow() {
        let width: CGFloat = 460
        let height: CGFloat = 260
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = "Thêm tài khoản Clone"
        win.isReleasedWhenClosed = false
        win.delegate = self
        win.level = .floating
        
        let content = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        win.contentView = content
        
        var y = height - 24
        
        func addLabel(_ title: String) -> NSTextField {
            y -= 18
            let label = NSTextField(labelWithString: title)
            label.font = NSFont.systemFont(ofSize: 11)
            label.textColor = .secondaryLabelColor
            label.frame = NSRect(x: 20, y: y, width: width - 40, height: 16)
            content.addSubview(label)
            return label
        }
        
        func addField(placeholder: String) -> NSTextField {
            y -= 28
            let field = NSTextField(string: "")
            field.placeholderString = placeholder
            field.bezelStyle = .roundedBezel
            field.isBezeled = true
            field.isBordered = true
            field.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
            field.frame = NSRect(x: 20, y: y, width: width - 40, height: 24)
            field.delegate = self
            content.addSubview(field)
            return field
        }
        
        _ = addLabel("Tên hiển thị")
        nameField = addField(placeholder: "VD: Business, Shop Online...")
        y -= 8
        _ = addLabel("Số điện thoại")
        phoneField = addField(placeholder: "0901234567")
        
        y -= 28
        let spinner = NSProgressIndicator(frame: NSRect(x: 20, y: y + 4, width: 16, height: 16))
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        content.addSubview(spinner)
        self.spinner = spinner
        
        let status = NSTextField(labelWithString: "")
        status.font = NSFont.systemFont(ofSize: 11)
        status.textColor = .secondaryLabelColor
        status.lineBreakMode = .byTruncatingTail
        status.frame = NSRect(x: 42, y: y, width: width - 62, height: 20)
        content.addSubview(status)
        statusLabel = status
        
        y -= 22
        let error = NSTextField(wrappingLabelWithString: "")
        error.font = NSFont.systemFont(ofSize: 11)
        error.textColor = .systemRed
        error.frame = NSRect(x: 20, y: y - 8, width: width - 40, height: 36)
        content.addSubview(error)
        errorLabel = error
        
        let cancel = NSButton(title: "Huỷ", target: self, action: #selector(cancelTapped))
        cancel.bezelStyle = .rounded
        cancel.keyEquivalent = "\u{1b}"
        cancel.frame = NSRect(x: width - 200, y: 16, width: 80, height: 28)
        content.addSubview(cancel)
        cancelButton = cancel
        
        let create = NSButton(title: "Tạo Clone", target: self, action: #selector(createTapped))
        create.bezelStyle = .rounded
        create.keyEquivalent = "\r"
        if #available(macOS 11.0, *) {
            create.hasDestructiveAction = false
        }
        create.frame = NSRect(x: width - 110, y: 16, width: 90, height: 28)
        content.addSubview(create)
        createButton = create
        
        if let parent = NSApp.keyWindow ?? NSApp.mainWindow {
            win.setFrameOrigin(NSPoint(
                x: parent.frame.midX - width / 2,
                y: parent.frame.midY - height / 2
            ))
        } else {
            win.center()
        }
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        win.makeFirstResponder(nameField)
        self.window = win
    }
    
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            if control === nameField {
                window?.makeFirstResponder(phoneField)
            } else {
                createTapped()
            }
            return true
        }
        return false
    }
    
    @objc private func cancelTapped() {
        guard !isCreating else { return }
        window?.performClose(nil)
        close()
    }
    
    @objc private func createTapped() {
        if isCreating { return }
        
        let name = nameField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let phone = phoneField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !name.isEmpty else {
            errorLabel?.stringValue = "Nhập tên hiển thị trước khi tạo clone."
            return
        }
        
        let store = CloneStore.shared
        guard store.canAddMore else {
            errorLabel?.stringValue = "Đã đạt giới hạn tối đa \(CloneStore.maxClones) tài khoản."
            return
        }
        if store.engine.isProcessing {
            errorLabel?.stringValue = "Đang tạo clone — vui lòng chờ."
            return
        }
        
        DiagnosticLogger.info("CREATE", "Form submit name='\(name)' phone='\(phone)'")
        isCreating = true
        errorLabel?.stringValue = ""
        statusLabel?.stringValue = "Đang chuẩn bị..."
        spinner?.startAnimation(nil)
        createButton?.isEnabled = false
        createButton?.keyEquivalent = ""
        cancelButton?.isEnabled = false
        nameField?.isEnabled = false
        phoneField?.isEnabled = false
        window?.displayIfNeeded()
        
        Task { @MainActor in
            let ticker = Task { @MainActor in
                while !Task.isCancelled {
                    self.statusLabel?.stringValue = store.engine.progressMessage
                    try? await Task.sleep(for: .milliseconds(250))
                }
            }
            do {
                let nextIndex = (store.clones.map(\.cloneIndex).max() ?? 0) + 1
                let clone = try await store.engine.createClone(index: nextIndex, name: name, phone: phone)
                ticker.cancel()
                store.addCreatedClone(clone)
                self.statusLabel?.stringValue = "Hoàn thành!"
                self.spinner?.stopAnimation(nil)
                try? await Task.sleep(for: .seconds(1.2))
                self.close()
            } catch {
                ticker.cancel()
                DiagnosticLogger.error("CREATE", "Lỗi tạo clone: \(error.localizedDescription)")
                self.isCreating = false
                self.spinner?.stopAnimation(nil)
                self.statusLabel?.stringValue = ""
                self.errorLabel?.stringValue = error.localizedDescription
                self.createButton?.isEnabled = true
                self.cancelButton?.isEnabled = true
                self.nameField?.isEnabled = true
                self.phoneField?.isEnabled = true
            }
        }
    }
}
