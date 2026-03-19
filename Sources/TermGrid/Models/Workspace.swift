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

enum ExplorerViewMode: String, Codable {
    case grid
    case list
}

struct Cell: Codable, Identifiable {
    let id: UUID
    var label: String
    var notes: String
    var workingDirectory: String
    var terminalLabel: String
    var splitTerminalLabel: String
    var explorerDirectory: String
    var explorerViewMode: ExplorerViewMode
    var splitDirection: String?   // "horizontal", "vertical", or nil
    var showExplorer: Bool

    init(id: UUID = UUID(), label: String = "", notes: String = "",
         workingDirectory: String = FileManager.default.homeDirectoryForCurrentUser.path,
         terminalLabel: String = "", splitTerminalLabel: String = "",
         explorerDirectory: String = "", explorerViewMode: ExplorerViewMode = .grid,
         splitDirection: String? = nil, showExplorer: Bool = false) {
        self.id = id
        self.label = label
        self.notes = notes
        self.workingDirectory = workingDirectory
        self.terminalLabel = terminalLabel
        self.splitTerminalLabel = splitTerminalLabel
        self.explorerDirectory = explorerDirectory
        self.explorerViewMode = explorerViewMode
        self.splitDirection = splitDirection
        self.showExplorer = showExplorer
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        label = (try? container.decode(String.self, forKey: .label)) ?? ""
        notes = (try? container.decode(String.self, forKey: .notes)) ?? ""
        workingDirectory = (try? container.decode(String.self, forKey: .workingDirectory))
            ?? FileManager.default.homeDirectoryForCurrentUser.path
        terminalLabel = (try? container.decode(String.self, forKey: .terminalLabel)) ?? ""
        splitTerminalLabel = (try? container.decode(String.self, forKey: .splitTerminalLabel)) ?? ""
        explorerDirectory = (try? container.decode(String.self, forKey: .explorerDirectory)) ?? ""
        explorerViewMode = (try? container.decode(ExplorerViewMode.self, forKey: .explorerViewMode)) ?? .grid
        splitDirection = try? container.decode(String.self, forKey: .splitDirection)
        showExplorer = (try? container.decode(Bool.self, forKey: .showExplorer)) ?? false
    }
}

struct Workspace: Codable {
    var schemaVersion: Int
    var gridLayout: GridPreset
    var cells: [Cell]
    var composeHistory: [ComposeHistoryEntry]

    init(schemaVersion: Int = 1, gridLayout: GridPreset = .two_by_two, cells: [Cell]? = nil,
         composeHistory: [ComposeHistoryEntry] = []) {
        self.schemaVersion = schemaVersion
        self.gridLayout = gridLayout
        self.cells = cells ?? (0..<gridLayout.cellCount).map { _ in Cell() }
        self.composeHistory = composeHistory
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
        composeHistory = (try? container.decode([ComposeHistoryEntry].self, forKey: .composeHistory)) ?? []
    }

    static var defaultWorkspace: Workspace {
        Workspace()
    }

    var visibleCells: [Cell] {
        Array(cells.prefix(gridLayout.cellCount))
    }
}
