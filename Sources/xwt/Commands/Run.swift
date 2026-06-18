import ArgumentParser
import Foundation

struct Run: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Build and run on the assigned simulator."
    )

    @Argument(help: "Branch name or slug.")
    var branch: String

    @Option(name: .shortAndLong, help: "Override the scheme to build.")
    var scheme: String?

    @Flag(name: .long, help: "Build only, don't install and launch.")
    var buildOnly = false

    @Option(name: .long, help: "Copy auth (keychain + session) from this simulator (name or UDID) on first install.")
    var copyAuthFrom: String?

    @Flag(name: .long, help: "Skip copying auth from a source simulator on first install.")
    var noCopyAuth = false

    func run() throws {
        let repoRoot = try ConfigLoader.detectMainRepoRoot()
        let repo = ConfigLoader.repoName(from: repoRoot)

        guard let task = try StateManager.find(repo: repo, branchOrSlug: branch) else {
            Terminal.errorLine("no task found for '\(branch)' — run 'xwt start \(branch)' first")
            throw ExitCode.failure
        }

        let buildScheme = scheme ?? task.scheme
        guard let buildScheme else {
            Terminal.errorLine("no scheme configured — set 'scheme' in .xwt.json or pass --scheme")
            throw ExitCode.failure
        }

        var args = ["xcodebuild"]

        if let workspace = task.workspace {
            args += ["-workspace", workspace]
        } else if let project = task.project {
            args += ["-project", project]
        }
        // For Swift Packages (task.package), pass no -workspace/-project flag;
        // xcodebuild discovers Package.swift from the working directory.

        args += [
            "-scheme", buildScheme,
            "-destination", "id=\(task.simulatorUDID)",
            "-derivedDataPath", task.derivedDataPath,
            "build",
        ]

        Terminal.out(.info, "  › Building \(buildScheme) for simulator \(task.simulatorName)…")
        Terminal.out(.muted, "    DerivedData: \(task.derivedDataPath)")
        Terminal.out(.muted, "    Destination: \(task.simulatorUDID)")
        Terminal.out()

        try ShellRunner.exec(args, cwd: task.package != nil ? task.worktreePath : nil)

        if buildOnly {
            Terminal.out()
            Terminal.out(.success, "  ✓ Build succeeded")
            return
        }

        // Find, install, and launch the built app
        let appPath: String
        let bundleID: String
        do {
            appPath = try BuiltApp.findApp(derivedDataPath: task.derivedDataPath)
            bundleID = try BuiltApp.readBundleID(appPath: appPath)
        } catch {
            Terminal.errorLine("\(error)")
            throw ExitCode.failure
        }

        Terminal.out()
        try Spinner.around(
            "Installing \(bundleID) on \(task.simulatorName)",
            final: "Installed \(bundleID) on \(task.simulatorName)"
        ) {
            try SimulatorService.install(udid: task.simulatorUDID, appPath: appPath)
        }

        // Copy auth (keychain + session cookies) on first install only — never
        // clobber an existing session. Use `xwt sync-auth` to force a re-sync.
        if !noCopyAuth, !SimulatorService.hasSession(udid: task.simulatorUDID, bundleID: bundleID),
           let sourceID = resolveAuthSource(repo: repo, repoRoot: repoRoot, task: task) {
            AuthSyncService.sync(
                fromSource: sourceID,
                toTargetUDID: task.simulatorUDID,
                bundleID: bundleID,
                includeKeychain: true,
                terminateTargetApp: false
            )
        }

        try Spinner.around(
            "Launching \(bundleID)",
            final: "Launched \(bundleID)"
        ) {
            try SimulatorService.launch(udid: task.simulatorUDID, bundleID: bundleID)
        }

        Terminal.out()
        Terminal.out(.success, "  ✓ Build, install, and launch succeeded")
    }

    // MARK: - Helpers

    /// Resolve the source simulator to copy auth from, by priority:
    /// `--copy-auth-from` > parent task's simulator > `sourceSimulator` in `.xwt.json`.
    private func resolveAuthSource(repo: String, repoRoot: String, task: TaskState) -> String? {
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
}
