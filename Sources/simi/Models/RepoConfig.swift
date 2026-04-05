import Foundation

/// Per-repo config loaded from `.simi.json` in the repository root.
struct RepoConfig: Codable {
    var workspace: String?
    var project: String?
    var scheme: String?
    var deviceType: String?
    var runtime: String?
    var sourceSimulator: String?

    static let fileName = ".simi.json"

    static func load(from repoRoot: String) throws -> RepoConfig? {
        let url = URL(fileURLWithPath: repoRoot).appendingPathComponent(Self.fileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(RepoConfig.self, from: data)
    }
}
