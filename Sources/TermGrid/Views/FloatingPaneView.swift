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
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                // Title bar — draggable
                HStack(spacing: 6) {
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

                Theme.divider.frame(height: 1)

                // Terminal + compose
                VStack(spacing: 0) {
                    TerminalContainerView(session: session)
                        .id(session.sessionID)

                    ComposeBox(agentType: session.detectedAgent, workingDirectory: session.composeWorkingDirectory) { text in
                        session.submitComposeText(text)
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

            // Industry-standard corner resize grip (three diagonal lines)
            resizeGrip
        }
        .shadow(color: .black.opacity(0.4), radius: 12)
        .offset(x: offset.width + dragOffset.width, y: offset.height + dragOffset.height)
    }

    // MARK: - Resize Grip (bottom-right corner, macOS standard diagonal lines)

    @ViewBuilder
    private var resizeGrip: some View {
        Canvas { context, size in
            let lineColor = Theme.headerIcon.opacity(0.5)
            // Three diagonal lines from bottom-left to top-right
            for i in 0..<3 {
                let offset = CGFloat(i) * 4.0
                let start = CGPoint(x: size.width - 4 - offset, y: size.height)
                let end = CGPoint(x: size.width, y: size.height - 4 - offset)
                var path = Path()
                path.move(to: start)
                path.addLine(to: end)
                context.stroke(path, with: .color(lineColor), lineWidth: 1)
            }
        }
        .frame(width: 14, height: 14)
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
        .padding(3)
    }

    // MARK: - Title Bar Button with Hover Tooltip

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
                .allowsHitTesting(false)
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                hoveredButton = hovering ? id : nil
            }
        }
    }
}
