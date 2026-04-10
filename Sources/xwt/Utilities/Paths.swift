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

    /// `~/worktrees/<repo>/<slug>/`
    static func worktreePath(repo: String, slug: String) -> URL {
        home.appendingPathComponent("worktrees").appendingPathComponent(repo).appendingPathComponent(slug)
    }

    /// `~/Library/Developer/CoreSimulator/Devices/<udid>/data/Library/Keychains/`
    static func simulatorKeychainDir(udid: String) -> URL {
        home
            .appendingPathComponent("Library/Developer/CoreSimulator/Devices")
            .appendingPathComponent(udid)
            .appendingPathComponent("data/Library/Keychains")
    }

    /// `~/Library/Developer/Xcode/DerivedData/xwt/<slug>/`
    static func derivedDataPath(slug: String) -> URL {
        home
            .appendingPathComponent("Library/Developer/Xcode/DerivedData")
            .appendingPathComponent("xwt")
            .appendingPathComponent(slug)
    }
}
