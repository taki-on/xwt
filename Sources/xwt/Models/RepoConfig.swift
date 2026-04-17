import Foundation

/// Per-repo config loaded from `.xwt.json` in the repository root.
struct RepoConfig: Codable {
    var workspace: String?
    var project: String?
    var package: String?
    var scheme: String?
    var deviceType: String?
    var runtime: String?
    var sourceSimulator: String?
    var worktreeDir: String?

    static let fileName = ".xwt.json"

    static func load(from repoRoot: String) throws -> RepoConfig? {
        let url = URL(fileURLWithPath: repoRoot).appendingPathComponent(Self.fileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(RepoConfig.self, from: data)
    }

    /// Write this config to `.xwt.json` in the given repo root.
    func save(to repoRoot: String) throws {
        let url = URL(fileURLWithPath: repoRoot).appendingPathComponent(Self.fileName)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try data.write(to: url, options: .atomic)
    }
}
