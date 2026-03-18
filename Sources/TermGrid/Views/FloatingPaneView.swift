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
    @State private var hoveredButton: String? = nil

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
            // Title bar — draggable, with resize handle on left
            HStack(spacing: 6) {
                // Resize handle — in title bar to avoid compose overlap
                Image(systemName: "arrow.up.backward.and.arrow.down.forward")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(Theme.accent.opacity(0.7))
                    .frame(width: 16, height: 16)
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

                Text("Quick Terminal")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Theme.headerText)

                Spacer()

                // Drop into grid button
                titleButton(
                    id: "grid",
                    systemName: "square.grid.2x2.fill",
                    label: "Add to grid",
                    action: { onDropIntoGrid() }
                )

                // Close button
                titleButton(
                    id: "close",
                    systemName: "xmark.circle.fill",
                    label: "Close",
                    action: { onDismiss() }
                )
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
            .zIndex(1) // Ensure tooltips show above terminal

            Theme.divider.frame(height: 1)

            // Terminal + compose
            VStack(spacing: 0) {
                TerminalContainerView(session: session)
                    .id(session.sessionID)

                ComposeBox { text in
                    session.send(text)
                }
            }
            .clipped()
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
        .offset(x: offset.width + dragOffset.width, y: offset.height + dragOffset.height)
    }

    @ViewBuilder
    private func titleButton(id: String, systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11))
                .foregroundColor(hoveredButton == id ? Theme.accent : Theme.headerIcon)
        }
        .buttonStyle(.borderless)
        .overlay(alignment: .top) {
            Text(label)
                .font(.system(size: 8, weight: .medium, design: .rounded))
                .foregroundColor(Theme.headerText)
                .fixedSize()
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Theme.cellBackground)
                        .shadow(color: .black.opacity(0.25), radius: 3, y: -2)
                )
                .offset(y: hoveredButton == id ? -22 : -14)
                .opacity(hoveredButton == id ? 1 : 0)
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                hoveredButton = hovering ? id : nil
            }
        }
    }
}
