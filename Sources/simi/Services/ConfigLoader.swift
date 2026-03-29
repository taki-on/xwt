import Foundation

enum ConfigLoader {
    /// Detect the git repo root from the current directory.
    static func detectRepoRoot() throws -> String {
        try ShellRunner.run("git", "rev-parse", "--show-toplevel")
    }

    /// Derive repo name from the repo root path.
    static func repoName(from repoRoot: String) -> String {
        URL(fileURLWithPath: repoRoot).lastPathComponent
    }

    /// Load `.simi.json` from the given repo root, returns nil if not found.
    static func loadConfig(repoRoot: String) throws -> RepoConfig? {
        try RepoConfig.load(from: repoRoot)
    }

    /// Load config with defaults filled in.
    static func loadConfigWithDefaults(repoRoot: String) throws -> RepoConfig {
        var config = try RepoConfig.load(from: repoRoot) ?? RepoConfig()
        if config.deviceType == nil { config.deviceType = "iPhone 17 Pro" }
        if config.runtime == nil { config.runtime = "iOS 26.3" }
        return config
    }
}
