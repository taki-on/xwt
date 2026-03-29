import Foundation

enum Paths {
    static let home = FileManager.default.homeDirectoryForCurrentUser

    /// `~/.simi/`
    static var simiRoot: URL { home.appendingPathComponent(".simi") }

    /// `~/.simi/repos/<repo>/`
    static func repoStateDir(repo: String) -> URL {
        simiRoot.appendingPathComponent("repos").appendingPathComponent(repo)
    }

    /// `~/.simi/repos/<repo>/<slug>.json`
    static func taskStatePath(repo: String, slug: String) -> URL {
        repoStateDir(repo: repo).appendingPathComponent("\(slug).json")
    }

    /// `~/worktrees/<repo>/<slug>/`
    static func worktreePath(repo: String, slug: String) -> URL {
        home.appendingPathComponent("worktrees").appendingPathComponent(repo).appendingPathComponent(slug)
    }

    /// `~/Library/Developer/Xcode/DerivedData/simi/<slug>/`
    static func derivedDataPath(slug: String) -> URL {
        home
            .appendingPathComponent("Library/Developer/Xcode/DerivedData")
            .appendingPathComponent("simi")
            .appendingPathComponent(slug)
    }
}
