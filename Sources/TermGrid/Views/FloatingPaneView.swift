import SwiftUI
import SwiftTerm

struct FloatingPaneView: View {
    let session: TerminalSession
    let onDismiss: () -> Void
    let onDropIntoGrid: () -> Void

    @State private var offset: CGSize = .zero
    @State private var dragOffset: CGSize = .zero
    @State private var paneSize: CGSize = CGSize(width: 350, height: 250)
    @State private var resizeDelta: CGSize = .zero

    private let minWidth: CGFloat = 280
    private let minHeight: CGFloat = 180
    private let maxWidth: CGFloat = 800
    private let maxHeight: CGFloat = 600

    private var currentWidth: CGFloat {
        min(max(paneSize.width + resizeDelta.width, minWidth), maxWidth)
    }

    private var currentHeight: CGFloat {
        min(max(paneSize.height + resizeDelta.height, minHeight), maxHeight)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Title bar — draggable
            HStack(spacing: 8) {
                Text("Quick Terminal")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Theme.headerText)
                Spacer()

                // Drop into grid button
                Button {
                    onDropIntoGrid()
                } label: {
                    Image(systemName: "rectangle.inset.filled.and.person.filled")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.headerIcon)
                }
                .buttonStyle(.borderless)
                .help("Add to grid")

                // Close button
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

            // Terminal + compose
            VStack(spacing: 0) {
                TerminalContainerView(session: session)
                    .id(session.sessionID)

                ComposeBox { text in
                    session.send(text)
                }
            }
        }
        .frame(width: currentWidth, height: currentHeight)
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
        // Resize handle — bottom-right corner
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 9))
                .foregroundColor(Theme.headerIcon.opacity(0.6))
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            resizeDelta = value.translation
                        }
                        .onEnded { value in
                            paneSize.width = currentWidth
                            paneSize.height = currentHeight
                            resizeDelta = .zero
                        }
                )
                .padding(4)
        }
        .offset(x: offset.width + dragOffset.width, y: offset.height + dragOffset.height)
    }
}
