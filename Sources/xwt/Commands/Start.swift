import ArgumentParser
import Foundation

struct Start: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Start a new task: create worktree, assign simulator, configure Copilot."
    )

    @Argument(help: "Branch name (e.g. feature/login-refactor).")
    var branch: String

    @Option(name: .shortAndLong, help: "Device type (e.g. 'iPhone 16 Pro Max'). Overrides .xwt.json.")
    var device: String?

    @Option(name: .shortAndLong, help: "iOS runtime (e.g. 'iOS 18.0'). Overrides .xwt.json.")
    var runtime: String?

    @Flag(name: .long, help: "Don't boot the simulator after creating it.")
    var noBoot = false

    @Option(name: .long, help: "Copy keychain from this simulator (name or UDID) to skip re-login.")
    var copyAuthFrom: String?

    @Flag(name: .long, help: "Skip keychain copy even when sourceSimulator is configured in .xwt.json.")
    var noCopyAuth = false

    func run() throws {
        let repoRoot = try ConfigLoader.detectRepoRoot()
        let repo = ConfigLoader.repoName(from: repoRoot)
        let slug = BranchSlug.slugify(branch)
        let config = try ConfigLoader.loadConfigWithDefaults(repoRoot: repoRoot)

        // Check for existing task (with slug collision detection)
        if let existing = try StateManager.find(repo: repo, branchOrSlug: branch) {
            if existing.branch == branch {
                print("⚠ Task already exists for '\(existing.branch)'. Use 'xwt remove \(branch)' first.")
            } else {
                print("⚠ Branch '\(branch)' conflicts with existing task for '\(existing.branch)' (both resolve to slug '\(slug)').")
                print("  Remove the existing task first: 'xwt remove \(existing.branch)'")
            }
            throw ExitCode.failure
        }

        let worktreePath = Paths.worktreePath(repo: repo, slug: slug, worktreeDir: config.worktreeDir).path
        let derivedDataPath = Paths.derivedDataPath(slug: slug).path
        let simName = "xwt-\(slug)"

        // Track created resources for rollback on failure
        var createdWorktree = false
        var createdSimulatorUDID: String?

        do {
            // 1. Create worktree
            print("📂 Creating worktree at \(worktreePath)...")
            try WorktreeService.add(repoRoot: repoRoot, branch: branch, path: worktreePath)
            createdWorktree = true

            // 2. Create or reuse simulator (CLI flags override .xwt.json)
            // loadConfigWithDefaults guarantees deviceType and runtime are non-nil
            let deviceType = device ?? config.deviceType!
            let runtimeStr = self.runtime ?? config.runtime!
            print("📱 Setting up simulator '\(simName)' (\(deviceType), \(runtimeStr))...")
            let (udid, reused) = try SimulatorService.createOrReuse(name: simName, deviceType: deviceType, runtime: runtimeStr)
            if !reused { createdSimulatorUDID = udid }
            print(reused ? "   ↳ Reusing existing simulator \(udid)" : "   ↳ Created new simulator \(udid)")

            // 3. Copy keychain from source simulator (before boot)
            if !noCopyAuth {
                let sourceID = copyAuthFrom ?? config.sourceSimulator
                if let sourceID = sourceID {
                    copyKeychain(from: sourceID, to: udid)
                }
            }

            // 4. Boot simulator
            if !noBoot {
                print("🚀 Booting simulator...")
                try SimulatorService.boot(udid: udid)
            }

            // 5. Create derived data directory
            try FileManager.default.createDirectory(atPath: derivedDataPath, withIntermediateDirectories: true)

            // 6. Save task state
            let task = TaskState(
                repo: repo,
                branch: branch,
                slug: slug,
                worktreePath: worktreePath,
                simulatorName: simName,
                simulatorUDID: udid,
                derivedDataPath: derivedDataPath,
                scheme: config.scheme,
                workspace: config.workspace,
                project: config.project,
                package: config.package,
                createdAt: Date()
            )
            try StateManager.save(task)

            // 7. Write Copilot instructions for XcodeBuildMCP auto-setup
            try StateManager.writeCopilotInstructions(task)

            // 8. Exclude generated files from git tracking in the worktree
            excludeFromGit(worktreePath: worktreePath)

            print("✅ Task started: \(branch)")
            print("   Worktree:     \(worktreePath)")
            print("   Simulator:    \(simName) (\(udid))")
            print("   DerivedData:  \(derivedDataPath)")
            print("")
            print("   cd \(worktreePath)")
        } catch {
            // Rollback on failure
            print("\n⚠ Task setup failed, rolling back...")
            try? StateManager.delete(repo: repo, slug: slug)
            if let simUDID = createdSimulatorUDID {
                try? SimulatorService.shutdown(udid: simUDID)
                try? SimulatorService.delete(udid: simUDID)
            }
            if createdWorktree {
                try? WorktreeService.remove(repoRoot: repoRoot, path: worktreePath)
            }
            try? FileManager.default.removeItem(atPath: derivedDataPath)
            throw error
        }
    }

    /// Copy keychain from a source simulator to the target. Non-fatal on failure.
    private func copyKeychain(from sourceID: String, to targetUDID: String) {
        do {
            let source = try SimulatorService.resolve(sourceID)
            print("🔑 Copying keychain from '\(source.name)' (\(source.udid))...")

            // If source is booted, shut it down to flush WAL, then reboot after copy
            let wasBooted = source.isBooted
            if wasBooted {
                print("   ↳ Shutting down source simulator to flush keychain...")
                try SimulatorService.shutdown(udid: source.udid)
                // Brief pause for WAL checkpoint
                Thread.sleep(forTimeInterval: 1)
            }

            try SimulatorService.copyKeychain(from: source.udid, to: targetUDID)

            if wasBooted {
                print("   ↳ Rebooting source simulator...")
                try SimulatorService.boot(udid: source.udid)
            }

            print("   ↳ Keychain copied successfully")
        } catch {
            print("   ⚠ Could not copy keychain: \(error)")
            print("   ↳ You may need to log in manually on the new simulator.")
        }
    }

    /// Add xwt-generated files to the repo's `.git/info/exclude` so they are never tracked.
    private func excludeFromGit(worktreePath: String) {
        guard let commonDir = try? ShellRunner.run("git", "-C", worktreePath, "rev-parse", "--git-common-dir") else {
            print("   ⚠ Could not resolve git common dir")
            return
        }
        let excludeURL = URL(fileURLWithPath: commonDir).appendingPathComponent("info/exclude")

        let patterns = [
            ".github/instructions/xwt.instructions.md",
        ]

        do {
            try FileManager.default.createDirectory(
                at: excludeURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            var content = ""
            if FileManager.default.fileExists(atPath: excludeURL.path) {
                content = try String(contentsOf: excludeURL, encoding: .utf8)
            }

            let existingLines = Set(content.components(separatedBy: .newlines))
            let newPatterns = patterns.filter { !existingLines.contains($0) }
            guard !newPatterns.isEmpty else { return }

            if !content.isEmpty && !content.hasSuffix("\n") {
                content += "\n"
            }
            content += newPatterns.joined(separator: "\n") + "\n"

            try content.write(to: excludeURL, atomically: true, encoding: .utf8)
        } catch {
            print("   ⚠ Could not update .git/info/exclude: \(error.localizedDescription)")
        }
    }
}
