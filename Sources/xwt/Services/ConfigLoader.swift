import Foundation

enum ConfigLoader {
    /// Detect the working tree root from the current directory.
    /// Inside a worktree this returns the **worktree** path, not the main repo root.
    /// Use `detectMainRepoRoot()` when you need the repo identity (name, config location).
    static func detectWorkingTreeRoot() throws -> String {
        try ShellRunner.run("git", "rev-parse", "--show-toplevel")
    }

    /// Detect the main repository root, even when running from inside a worktree.
    /// Uses `--git-common-dir` to find the shared `.git` directory and derives the repo root from it.
    static func detectMainRepoRoot() throws -> String {
        let commonDir = try ShellRunner.run("git", "rev-parse", "--path-format=absolute", "--git-common-dir")
        let commonURL = URL(fileURLWithPath: commonDir)
        // The common dir is the `.git` directory (or `.git/worktrees/...` internals).
        // Walk up to the parent of `.git`.
        var url = commonURL
        while url.lastPathComponent != ".git" && url.path != "/" {
            url = url.deletingLastPathComponent()
        }
        return url.deletingLastPathComponent().path
    }

    /// Derive repo name from the repo root path.
    static func repoName(from repoRoot: String) -> String {
        URL(fileURLWithPath: repoRoot).lastPathComponent
    }

    /// Load `.xwt.json` from the given repo root, returns nil if not found.
    static func loadConfig(repoRoot: String) throws -> RepoConfig? {
        try RepoConfig.load(from: repoRoot)
    }

    /// Load config with defaults filled in.
    static func loadConfigWithDefaults(repoRoot: String) throws -> RepoConfig {
        var config = try RepoConfig.load(from: repoRoot) ?? RepoConfig()
        if config.deviceType == nil { config.deviceType = "iPhone 17 Pro" }
        if config.runtime == nil { config.runtime = "iOS 26.4" }
        return config
    }
}
