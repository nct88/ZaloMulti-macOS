// ContentView.swift
// ZaloMulti
//
// Layout tổng thể: Main Content (trái) + Sidebar (phải)
// Rebuild v2.1 — @EnvironmentObject pattern.

import SwiftUI

struct ContentView: View {
    @ObservedObject var cloneStore: CloneStore
    @State private var showSidebar = true
    @State private var showAddModal = false
    
    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                NotificationBarView()
                DashboardView(onAddClone: openAddModal)
            }
            .frame(maxWidth: .infinity)
            
            if showSidebar {
                Rectangle()
                    .fill(Color(nsColor: .separatorColor))
                    .frame(width: 1)
                
                SidebarView()
                    .frame(width: 240)
            }
        }
        .overlay {
            if showAddModal {
                ZStack {
                    Rectangle()
                        .fill(Color.black.opacity(0.4))
                        .ignoresSafeArea()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    
                    AddCloneView(isPresented: $showAddModal)
                }
            }
        }
        .onChange(of: cloneStore.showAddCloneSheet) { _, isOn in
            showAddModal = isOn
        }
        .onChange(of: showAddModal) { _, isOn in
            if cloneStore.showAddCloneSheet != isOn {
                cloneStore.showAddCloneSheet = isOn
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: openAddModal) {
                    Label("Thêm tài khoản", systemImage: "plus")
                }
                .disabled(!cloneStore.canAddMore || showAddModal)
                .help("Thêm tài khoản clone")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showSidebar.toggle()
                } label: {
                    Image(systemName: "sidebar.right")
                }
                .help("Ẩn/Hiện thanh bên")
            }
        }
        .alert("Lỗi", isPresented: $cloneStore.showError) {
            Button("OK") { cloneStore.showError = false }
        } message: {
            Text(cloneStore.errorMessage ?? "Đã xảy ra lỗi không xác định")
        }
    }
    
    private func openAddModal() {
        DiagnosticLogger.info("UI", "Mở form thêm tài khoản")
        showAddModal = true
        cloneStore.showAddCloneSheet = true
    }
}
