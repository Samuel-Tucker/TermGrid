import SwiftUI
import SwiftTerm

struct FloatingPaneView: View {
    let session: TerminalSession
    let onDismiss: () -> Void

    @State private var offset: CGSize = .zero
    @State private var dragOffset: CGSize = .zero

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Quick Terminal")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Theme.headerText)
                Spacer()
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.headerIcon)
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Theme.headerBackground)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        dragOffset = value.translation
                    }
                    .onEnded { value in
                        offset.width += value.translation.width
                        offset.height += value.translation.height
                        dragOffset = .zero
                    }
            )

            Theme.divider.frame(height: 1)

            VStack(spacing: 0) {
                TerminalContainerView(session: session)
                    .id(session.sessionID)

                ComposeBox { text in
                    session.send(text)
                }
            }
        }
        .frame(width: 350, height: 250)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Theme.cellBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.accent, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.4), radius: 12)
        .offset(x: offset.width + dragOffset.width, y: offset.height + dragOffset.height)
    }
}
