import Foundation

enum Paths {
    static let home = FileManager.default.homeDirectoryForCurrentUser

    /// `~/.xwt/`
    static var xwtRoot: URL { home.appendingPathComponent(".xwt") }

    /// `~/.xwt/repos/<repo>/`
    static func repoStateDir(repo: String) -> URL {
        xwtRoot.appendingPathComponent("repos").appendingPathComponent(repo)
    }

    /// `~/.xwt/repos/<repo>/<slug>.json`
    static func taskStatePath(repo: String, slug: String) -> URL {
        repoStateDir(repo: repo).appendingPathComponent("\(slug).json")
    }

    /// `~/.xwt/last-task-path` — written by `xwt start` after success,
    /// read by the shell-integration wrapper to auto-cd into the new worktree.
    static var lastTaskPathFile: URL {
        xwtRoot.appendingPathComponent("last-task-path")
    }

    /// `<worktreeDir>/<repo>/<slug>/` — defaults to `~/worktrees` when no custom dir is set.
    static func worktreePath(repo: String, slug: String, worktreeDir: String? = nil) -> URL {
        let base: URL
        if let dir = worktreeDir {
            base = URL(fileURLWithPath: (dir as NSString).expandingTildeInPath)
        } else {
            base = home.appendingPathComponent("worktrees")
        }
        return base.appendingPathComponent(repo).appendingPathComponent(slug)
    }

    /// `~/Library/Developer/CoreSimulator/Devices/<udid>/data/Library/Keychains/`
    static func simulatorKeychainDir(udid: String) -> URL {
        home
            .appendingPathComponent("Library/Developer/CoreSimulator/Devices")
            .appendingPathComponent(udid)
            .appendingPathComponent("data/Library/Keychains")
    }

    /// `~/Library/Developer/Xcode/DerivedData/xwt/<repo>/<slug>/`
    static func derivedDataPath(repo: String, slug: String) -> URL {
        home
            .appendingPathComponent("Library/Developer/Xcode/DerivedData")
            .appendingPathComponent("xwt")
            .appendingPathComponent(repo)
            .appendingPathComponent(slug)
    }
}
