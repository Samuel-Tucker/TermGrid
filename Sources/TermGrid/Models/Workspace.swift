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
    var workingDirectory: String

    init(id: UUID = UUID(), label: String = "", notes: String = "",
         workingDirectory: String = FileManager.default.homeDirectoryForCurrentUser.path) {
        self.id = id
        self.label = label
        self.notes = notes
        self.workingDirectory = workingDirectory
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        label = (try? container.decode(String.self, forKey: .label)) ?? ""
        notes = (try? container.decode(String.self, forKey: .notes)) ?? ""
        workingDirectory = (try? container.decode(String.self, forKey: .workingDirectory))
            ?? FileManager.default.homeDirectoryForCurrentUser.path
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
        var loadedCells = try container.decode([Cell].self, forKey: .cells)
        let needed = gridLayout.cellCount
        if loadedCells.count < needed {
            loadedCells.append(contentsOf: (0..<(needed - loadedCells.count)).map { _ in Cell() })
        }
        cells = loadedCells
    }

    static var defaultWorkspace: Workspace {
        Workspace()
    }

    var visibleCells: [Cell] {
        Array(cells.prefix(gridLayout.cellCount))
    }
}
