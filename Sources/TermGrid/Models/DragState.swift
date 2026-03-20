import Foundation
import SwiftUI

@MainActor
@Observable
final class PanelDragState {
    var draggingCellID: UUID? = nil
    var dropTargetCellID: UUID? = nil
    var dragOffset: CGSize = .zero
    var isDragging: Bool { draggingCellID != nil }

    func reset() {
        draggingCellID = nil
        dropTargetCellID = nil
        dragOffset = .zero
    }
}
