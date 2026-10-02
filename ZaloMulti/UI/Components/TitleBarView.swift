import SwiftUI

struct TitleBarView: View {
    @Binding var showSidebar: Bool
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        HStack(spacing: 12) {

            Color.clear
                .frame(width: 68, height: 52)

            Spacer()

            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 5)
                    .fill(LinearGradient(
                        colors: [.zaloPrimary, .zaloDark],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: 18, height: 18)
                    .overlay(
                        Text("Z")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundColor(.white)
                    )

                Text("zDesk")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
            }

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showSidebar.toggle()
                }
            } label: {
                Image(systemName: "sidebar.right")
                    .font(.system(size: 14))
                    .foregroundStyle(showSidebar ? .primary : .secondary)
            }
            .buttonStyle(.plain)
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
            .padding(.trailing, 12)
        }
        .frame(height: 52)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}
