// ContentView.swift
// ZaloMulti

import SwiftUI

struct ContentView: View {
    @ObservedObject var cloneStore: CloneStore
    @State private var showSidebar = true
    @State private var listTick = 0
    
    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    NotificationBarView()
                    DashboardView(store: cloneStore, onAddClone: { cloneStore.showAddCloneSheet = true })
                }
                .frame(maxWidth: .infinity)
                
                if showSidebar {
                    Rectangle()
                        .fill(Color(nsColor: .separatorColor))
                        .frame(width: 1)
                    
                    SidebarView(store: cloneStore)
                        .frame(width: 240)
                }
            }
            .id(listTick)
            
            if cloneStore.showAddCloneSheet {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                
                AddCloneView(store: cloneStore)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: CloneStore.listDidChange)) { _ in
            listTick += 1
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    cloneStore.showAddCloneSheet = true
                } label: {
                    Label("Thêm tài khoản", systemImage: "plus")
                }
                .disabled(!cloneStore.canAddMore || cloneStore.showAddCloneSheet)
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
