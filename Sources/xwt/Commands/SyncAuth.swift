import ArgumentParser
import Foundation

struct SyncAuth: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sync-auth",
        abstract: "Copy auth (keychain + session cookies) from a source simulator into a task's simulator."
    )

    @Argument(help: "Branch name or slug.")
    var branch: String

    @Option(name: .long, help: "Source simulator (name or UDID). Overrides parent task / .xwt.json.")
    var copyAuthFrom: String?

    @Option(name: .long, help: "App bundle identifier. Defaults to the built app's CFBundleIdentifier.")
    var bundleId: String?

    func run() throws {
        let repoRoot = try ConfigLoader.detectMainRepoRoot()
        let repo = ConfigLoader.repoName(from: repoRoot)

        guard let task = try StateManager.find(repo: repo, branchOrSlug: branch) else {
            Terminal.errorLine("no task found for '\(branch)' — run 'xwt start \(branch)' first")
            throw ExitCode.failure
        }

        // Resolve source: --copy-auth-from > parent task's sim > config.sourceSimulator
        guard let sourceID = resolveSource(repo: repo, repoRoot: repoRoot, task: task) else {
            Terminal.errorLine("no source simulator — pass --copy-auth-from or set 'sourceSimulator' in .xwt.json")
            throw ExitCode.failure
        }

        // Resolve bundle ID: --bundle-id > built app's CFBundleIdentifier
        let resolvedBundleID: String
        if let bundleId {
            resolvedBundleID = bundleId
        } else if let derived = builtBundleID(task: task) {
            resolvedBundleID = derived
        } else {
            Terminal.errorLine("could not determine bundle id — build first with 'xwt run \(branch)' or pass --bundle-id")
            throw ExitCode.failure
        }

        let result = AuthSyncService.sync(
            fromSource: sourceID,
            toTargetUDID: task.simulatorUDID,
            bundleID: resolvedBundleID,
            includeKeychain: true,
            quiesceTarget: true
        )

        switch result {
        case .failed:
            throw ExitCode.failure
        case .skipped:
            Terminal.out()
            Terminal.out(.muted, "    nothing to sync")
        case .copied:
            Terminal.out()
            Terminal.out(.success, "  ✓ Auth synced to \(task.simulatorName)")
            Terminal.out("    Bundle:     \(resolvedBundleID)")
            Terminal.out("    Simulator:  \(task.simulatorName) \(Terminal.styled("(\(task.simulatorUDID))", .muted))")
            Terminal.noteLine("relaunch the app to pick up the copied session")
        }
    }

    // MARK: - Helpers

    /// Resolve the source simulator by priority:
    /// `--copy-auth-from` > parent task's simulator > `sourceSimulator` in `.xwt.json`.
    private func resolveSource(repo: String, repoRoot: String, task: TaskState) -> String? {
        if let copyAuthFrom { return copyAuthFrom }
        if let parentSlug = task.parentSlug,
           let parent = try? StateManager.load(repo: repo, slug: parentSlug) {
            return parent.simulatorUDID
        }
        if let config = try? RepoConfig.load(from: repoRoot) {
            return config.sourceSimulator
        }
        return nil
    }

    /// Read the bundle ID from the app built into the task's DerivedData.
    private func builtBundleID(task: TaskState) -> String? {
        guard let appPath = try? BuiltApp.findApp(derivedDataPath: task.derivedDataPath),
              let bundleID = try? BuiltApp.readBundleID(appPath: appPath) else {
            return nil
        }
        return bundleID
    }
}
