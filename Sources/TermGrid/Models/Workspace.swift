import Foundation

enum GridPreset: String, Codable, CaseIterable {
    case one_by_one = "1x1"
    case two_by_one = "2x1"
    case one_by_two = "1x2"
    case two_by_two = "2x2"
    case three_by_two = "3x2"
    case two_by_three = "2x3"
    case three_by_three = "3x3"

    var columns: Int {
        switch self {
        case .one_by_one, .one_by_two: return 1
        case .two_by_one, .two_by_two, .two_by_three: return 2
        case .three_by_two, .three_by_three: return 3
        }
    }

    var rows: Int {
        switch self {
        case .one_by_one, .two_by_one: return 1
        case .one_by_two, .two_by_two, .three_by_two: return 2
        case .two_by_three, .three_by_three: return 3
        }
    }

    var cellCount: Int { columns * rows }
}

struct Cell: Codable, Identifiable {
    let id: UUID
    var label: String
    var notes: String

    init(id: UUID = UUID(), label: String = "", notes: String = "") {
        self.id = id
        self.label = label
        self.notes = notes
    }
}

struct Workspace: Codable {
    var schemaVersion: Int
    var gridLayout: GridPreset
    var cells: [Cell]

    init(schemaVersion: Int = 1, gridLayout: GridPreset = .two_by_two, cells: [Cell]? = nil) {
        self.schemaVersion = schemaVersion
        self.gridLayout = gridLayout
        self.cells = cells ?? (0..<gridLayout.cellCount).map { _ in Cell() }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = (try? container.decode(Int.self, forKey: .schemaVersion)) ?? 1
        gridLayout = (try? container.decode(GridPreset.self, forKey: .gridLayout)) ?? .two_by_two
        cells = try container.decode([Cell].self, forKey: .cells)
    }

    static var defaultWorkspace: Workspace {
        Workspace()
    }

    var visibleCells: [Cell] {
        let needed = gridLayout.cellCount
        if cells.count >= needed {
            return Array(cells.prefix(needed))
        }
        return cells + (0..<(needed - cells.count)).map { _ in Cell() }
    }
}
