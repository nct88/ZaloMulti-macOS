import Foundation
import SwiftUI
import Darwin

@MainActor
final class CloneStore: ObservableObject {

    static let shared = CloneStore()

    static let maxClones = 4

    @Published var clones: [CloneAccount] = []
    @Published var showAddCloneSheet = false {
        didSet {
            guard oldValue != showAddCloneSheet else { return }
            DiagnosticLogger.info("STORE", "showAddCloneSheet \(oldValue) → \(showAddCloneSheet)")
        }
    }
    @Published var errorMessage: String?
    @Published var showError = false

    var canAddMore: Bool { clones.count < Self.maxClones }

    func openAddClone(source: String = "unknown") {
        DiagnosticLogger.info("STORE", "openAddClone source=\(source) canAddMore=\(canAddMore) count=\(clones.count) sheetShown=\(showAddCloneSheet)")
        guard canAddMore else {
            errorMessage = "Đã đạt giới hạn tối đa \(Self.maxClones) tài khoản."
            showError = true
            return
        }
        showAddCloneSheet = true
    }

    let engine = ZaloCloneEngine()
    let processManager = ProcessManager()

    private let storageKey = "clone_accounts_v1"
    private var syncTimer: Timer?

    init() {
        DiagnosticLogger.info("STORE", "CloneStore khởi tạo...")
        loadClones()
        DiagnosticLogger.info("STORE", "Đã load \(clones.count) clones từ storage")
        startSyncTimer()
    }

    private func startSyncTimer() {
        syncTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.syncRunningStatus()
            }
        }
    }

    func addClone(name: String, phone: String) {
        guard canAddMore else {
            errorMessage = "Đã đạt giới hạn tối đa \(Self.maxClones) tài khoản."
            showError = true
            DiagnosticLogger.warning("STORE", "addClone bị chặn: đã đạt giới hạn \(Self.maxClones) TK")
            return
        }
        let nextIndex = (clones.map(\.cloneIndex).max() ?? 0) + 1
        DiagnosticLogger.info("STORE", "addClone: name='\(name)', nextIndex=\(nextIndex)")

        Task {
            do {
                let clone = try await engine.createClone(
                    index: nextIndex,
                    name: name,
                    phone: phone
                )
                addCreatedClone(clone)
            } catch {
                errorMessage = error.localizedDescription
                showError = true
                DiagnosticLogger.error("STORE", "addClone thất bại", error: error)
            }
        }
    }

    func addCreatedClone(_ clone: CloneAccount) {
        var next = clones
        if !next.contains(where: { $0.id == clone.id }) {
            next.append(clone)
        }
        clones = next
        saveClones()
        DiagnosticLogger.success("STORE", "Clone '\(clone.name)' đã thêm (total=\(clones.count))")
    }

    func updateClone(_ updated: CloneAccount) {
        guard let index = clones.firstIndex(where: { $0.id == updated.id }) else { return }
        clones[index] = updated
        saveClones()
    }

    func deleteClone(_ clone: CloneAccount) {
        DiagnosticLogger.info("STORE", "deleteClone: '\(clone.name)'")

        if let pid = clone.processID {
            kill(pid, SIGKILL)
        }
        processManager.runningProcesses.removeValue(forKey: clone.id)

        do {
            try engine.deleteClone(clone)
            clones = clones.filter { $0.id != clone.id }
            saveClones()
            DiagnosticLogger.success("STORE", "Đã xoá '\(clone.name)' khỏi danh sách — còn \(clones.count)")
        } catch {
            errorMessage = "Lỗi xoá files: \(error.localizedDescription)"
            showError = true
            DiagnosticLogger.error("STORE", "deleteClone thất bại", error: error)
        }
    }

    func launchClone(_ clone: CloneAccount) {
        guard let index = clones.firstIndex(where: { $0.id == clone.id }) else { return }

        do {
            let pid = try processManager.launchClone(clone)
            clones[index].status = .running
            clones[index].processID = pid
            clones[index].lastOpenedAt = Date()
            saveClones()
            DiagnosticLogger.success("STORE", "Clone '\(clone.name)' đang chạy — PID=\(pid)")
        } catch {
            if case CloneError.alreadyRunning = error {
                clones[index].status = .running
                saveClones()
            } else {
                errorMessage = error.localizedDescription
                showError = true
                DiagnosticLogger.error("STORE", "launchClone thất bại", error: error)
            }
        }
    }

    func stopClone(_ clone: CloneAccount) {
        guard let index = clones.firstIndex(where: { $0.id == clone.id }) else { return }
        processManager.stopClone(clone)
        clones[index].status = .stopped
        clones[index].processID = nil
        saveClones()
    }

    func stopAllClones() {
        DiagnosticLogger.info("STORE", "stopAllClones — \(clones.count) clones")

        for clone in clones where clone.status == .running {
            let script = "tell application id \"\(clone.bundleID)\" to quit"
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            proc.arguments = ["-e", script]
            proc.standardOutput = FileHandle.nullDevice
            proc.standardError = FileHandle.nullDevice
            try? proc.run()
        }

        processManager.stopAllClones()
        for i in clones.indices {
            clones[i].status = .stopped
            clones[i].processID = nil
        }
        saveClones()
    }

    var runningCount: Int { clones.filter { $0.status == .running }.count }
    var totalCount: Int { clones.count }

    private func syncRunningStatus() {
        var changed = false

        for i in clones.indices {
            let clone = clones[i]
            guard clone.status == .running else { continue }

            if let pid = clone.processID {
                if !ProcessManager.isRunning(pid: pid) {
                    clones[i].status = .stopped
                    clones[i].processID = nil
                    changed = true
                    DiagnosticLogger.info("SYNC", "'\(clone.name)' running→stopped (PID \(pid) exited)")
                }
            } else {
                clones[i].status = .stopped
                changed = true
            }
        }

        if changed { saveClones() }
    }

    func saveClones() {
        do {
            let data = try JSONEncoder().encode(clones)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            DiagnosticLogger.error("STORE", "saveClones FAILED", error: error)
        }
    }

    private func loadClones() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        do {
            clones = try JSONDecoder().decode([CloneAccount].self, from: data)
        } catch {
            DiagnosticLogger.error("STORE", "loadClones: decode FAILED", error: error)
        }
    }

    func startBackgroundSync() {
        Task { @MainActor in
            syncProcessStatus()
        }
    }

    private func syncProcessStatus() {
        DiagnosticLogger.info("STORE", "Sync process status cho \(clones.count) clones...")
        var changed = 0

        for i in clones.indices {
            if let pid = clones[i].processID, ProcessManager.isRunning(pid: pid) {
                clones[i].status = .running
            } else {
                let orphanAlive = ProcessManager.checkCloneRunning(
                    cloneIndex: clones[i].cloneIndex, knownPID: nil
                )
                if orphanAlive {
                    clones[i].status = .running
                    DiagnosticLogger.info("STORE", "  '\(clones[i].name)' → running (orphan recovered)")
                } else {
                    if clones[i].status == .running { changed += 1 }
                    clones[i].status = .stopped
                    clones[i].processID = nil
                }
            }
        }

        if changed > 0 { saveClones() }
    }
}
