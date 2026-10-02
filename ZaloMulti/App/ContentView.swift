import SwiftUI

struct ContentView: View {
    @ObservedObject var cloneStore: CloneStore
    @State private var showSidebar = true

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                NotificationBarView()
                DashboardView(store: cloneStore, onAddClone: { cloneStore.openAddClone(source: "dashboard-card") })
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

        .sheet(isPresented: $cloneStore.showAddCloneSheet) {
            AddCloneView(store: cloneStore)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    cloneStore.openAddClone(source: "toolbar")
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
