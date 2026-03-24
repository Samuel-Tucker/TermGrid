import SwiftUI

struct ScratchPadPopoutView: View {
    @Binding var text: String
    let onDismiss: () -> Void

    @State private var offset: CGSize = .zero
    @State private var dragOffset: CGSize = .zero
    @State private var size: CGSize = CGSize(width: 400, height: 300)
    @State private var resizeDelta: CGSize = .zero
    @FocusState private var editorFocused: Bool

    private var currentWidth: CGFloat {
        min(max(size.width + resizeDelta.width, 300), 600)
    }
    private var currentHeight: CGFloat {
        min(max(size.height + resizeDelta.height, 200), 500)
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                // Draggable title bar
                HStack {
                    Text("Scratch Pad")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Theme.headerText)
                    Spacer()
                    Button { onDismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.headerIcon)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Theme.headerBackground)
                .gesture(
                    DragGesture()
                        .onChanged { dragOffset = $0.translation }
                        .onEnded {
                            offset.width += $0.translation.width
                            offset.height += $0.translation.height
                            dragOffset = .zero
                        }
                )

                Theme.divider.frame(height: 1)

                TextEditor(text: $text)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(Theme.scratchPadText)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .focused($editorFocused)
                    .onAppear {
                        DispatchQueue.main.async { editorFocused = true }
                    }
            }
            .frame(width: currentWidth, height: currentHeight)
            .background(Theme.cellBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(color: .black.opacity(0.5), radius: 16)

            // Resize grip
            resizeGrip
        }
        .offset(x: offset.width + dragOffset.width,
                y: offset.height + dragOffset.height)
        .onKeyPress(.escape) {
            onDismiss()
            return .handled
        }
    }

    private var resizeGrip: some View {
        Canvas { context, canvasSize in
            for i in 0..<3 {
                let off = CGFloat(i) * 4.0
                var path = Path()
                path.move(to: CGPoint(x: canvasSize.width - 4 - off, y: canvasSize.height))
                path.addLine(to: CGPoint(x: canvasSize.width, y: canvasSize.height - 4 - off))
                context.stroke(path, with: .color(Theme.headerIcon.opacity(0.4)), lineWidth: 1)
            }
        }
        .frame(width: 14, height: 14)
        .contentShape(Rectangle())
        .gesture(
            DragGesture()
                .onChanged { resizeDelta = $0.translation }
                .onEnded { _ in
                    size.width = currentWidth
                    size.height = currentHeight
                    resizeDelta = .zero
                }
        )
    }
}
