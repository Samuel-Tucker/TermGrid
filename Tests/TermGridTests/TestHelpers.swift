import Foundation
@testable import TermGrid

enum TestHelpers {
    static func encodeWorkspace(_ workspace: Workspace) throws -> Data {
        try JSONEncoder().encode(workspace)
    }

    static func decodeWorkspace(from data: Data) throws -> Workspace {
        try JSONDecoder().decode(Workspace.self, from: data)
    }

    static func decodeWorkspace(fromJSON json: String) throws -> Workspace {
        let data = json.data(using: .utf8)!
        return try JSONDecoder().decode(Workspace.self, from: data)
    }
}
