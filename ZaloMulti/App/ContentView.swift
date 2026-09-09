// ContentView.swift
// ZaloMulti
//
// Layout tổng thể: Main Content (trái) + Sidebar (phải)
// Rebuild v2.1 — @EnvironmentObject pattern.

import SwiftUI

struct ContentView: View {
    @ObservedObject var cloneStore: CloneStore
    @State private var showSidebar = true
    
    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                NotificationBarView()
                DashboardView(store: cloneStore, onAddClone: { AddCloneWindow.shared.present() })
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
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    AddCloneWindow.shared.present()
                } label: {
                    Label("Thêm tài khoản", systemImage: "plus")
                }
                .disabled(!cloneStore.canAddMore)
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
}
