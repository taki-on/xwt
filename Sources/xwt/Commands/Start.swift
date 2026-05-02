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

    @Option(name: .long, help: "Base branch to stack on (e.g. feature/auth). Creates the new branch from this base.")
    var base: String?

    @Flag(name: .long, help: "Don't auto-detect base branch from current worktree.")
    var noBase = false

    @Flag(name: .long, help: "Create own simulator and derived data instead of sharing the parent's.")
    var isolated = false

    func run() throws {
        let mainRepoRoot = try ConfigLoader.detectMainRepoRoot()
        let repo = ConfigLoader.repoName(from: mainRepoRoot)
        let slug = BranchSlug.slugify(branch)
        let config = try ConfigLoader.loadConfigWithDefaults(repoRoot: mainRepoRoot)

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

        // Resolve base branch for stacking
        let resolvedBase = try resolveBaseBranch(repo: repo)

        let worktreePath = Paths.worktreePath(repo: repo, slug: slug, worktreeDir: config.worktreeDir).path

        // Decide whether to share parent's simulator and derived data
        let shareResources = resolvedBase?.parentTask != nil && !isolated

        let derivedDataPath: String
        let simName: String
        let parentSimUDID: String?

        if shareResources, let parentTask = resolvedBase?.parentTask {
            derivedDataPath = parentTask.derivedDataPath
            simName = parentTask.simulatorName
            parentSimUDID = parentTask.simulatorUDID
        } else {
            derivedDataPath = Paths.derivedDataPath(slug: slug).path
            simName = "xwt-\(slug)"
            parentSimUDID = nil
        }

        // Track created resources for rollback on failure
        var createdWorktree = false
        var createdSimulatorUDID: String?

        do {
            // 1. Create worktree (from base branch if stacking)
            if let baseInfo = resolvedBase {
                print("🔗 Stacking on '\(baseInfo.branch)'\(baseInfo.autoDetected ? " (auto-detected from current worktree)" : "")")
            }
            print("📂 Creating worktree at \(worktreePath)...")
            try WorktreeService.add(repoRoot: mainRepoRoot, branch: branch, path: worktreePath, baseBranch: resolvedBase?.branch)
            createdWorktree = true

            let udid: String

            if let sharedUDID = parentSimUDID {
                // Sharing parent's simulator — no creation or keychain copy needed
                udid = sharedUDID
                print("📱 Sharing simulator '\(simName)' from '\(resolvedBase!.branch)'")
                print("   ↳ Simulator \(udid)")
                print("   ↳ DerivedData \(derivedDataPath)")
            } else {
                // 2. Create or reuse simulator (CLI flags override .xwt.json)
                let deviceType = device ?? config.deviceType!
                let runtimeStr = self.runtime ?? config.runtime!
                print("📱 Setting up simulator '\(simName)' (\(deviceType), \(runtimeStr))...")
                let (newUDID, reused) = try SimulatorService.createOrReuse(name: simName, deviceType: deviceType, runtime: runtimeStr)
                udid = newUDID
                if !reused { createdSimulatorUDID = udid }
                print(reused ? "   ↳ Reusing existing simulator \(udid)" : "   ↳ Created new simulator \(udid)")

                // 3. Copy keychain (priority: --copy-auth-from > parent's simulator > sourceSimulator)
                if !noCopyAuth {
                    let sourceID = copyAuthFrom
                        ?? resolvedBase?.parentTask?.simulatorUDID
                        ?? config.sourceSimulator
                    if let sourceID = sourceID {
                        copyKeychain(from: sourceID, to: udid)
                    }
                }

                // 4. Create derived data directory
                try FileManager.default.createDirectory(atPath: derivedDataPath, withIntermediateDirectories: true)
            }

            // 5. Boot simulator (idempotent — no-op if already booted)
            if !noBoot {
                print("🚀 Booting simulator...")
                try SimulatorService.boot(udid: udid)
            }

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
                createdAt: Date(),
                parentBranch: resolvedBase?.branch,
                parentSlug: resolvedBase?.parentTask?.slug
            )
            try StateManager.save(task)

            // 7. Write Copilot instructions for XcodeBuildMCP auto-setup
            try StateManager.writeCopilotInstructions(task)

            // 8. Write Claude Code instructions for XcodeBuildMCP auto-setup
            try StateManager.writeClaudeCodeInstructions(task)

            // 9. Exclude generated files from git tracking in the worktree
            excludeFromGit(worktreePath: worktreePath)

            print("✅ Task started: \(branch)")
            print("   Worktree:     \(worktreePath)")
            print("   Simulator:    \(simName) (\(udid))\(shareResources ? " (shared)" : "")")
            print("   DerivedData:  \(derivedDataPath)\(shareResources ? " (shared)" : "")")
            if let baseInfo = resolvedBase {
                print("   Base:         \(baseInfo.branch)")
            }
            print("")
            print("   cd \(worktreePath)")
        } catch {
            // Rollback on failure — never delete parent's shared resources
            print("\n⚠ Task setup failed, rolling back...")
            try? StateManager.delete(repo: repo, slug: slug)
            if let simUDID = createdSimulatorUDID {
                try? SimulatorService.shutdown(udid: simUDID)
                try? SimulatorService.delete(udid: simUDID)
            }
            if createdWorktree {
                try? WorktreeService.remove(repoRoot: mainRepoRoot, path: worktreePath)
            }
            if !shareResources {
                try? FileManager.default.removeItem(atPath: derivedDataPath)
            }
            throw error
        }
    }

    // MARK: - Base branch resolution

    private struct ResolvedBase {
        let branch: String
        let parentTask: TaskState?
        let autoDetected: Bool
    }

    /// Resolve the base branch for stacking.
    /// Priority: --base explicit > auto-detected from cwd > nil (fork from HEAD).
    private func resolveBaseBranch(repo: String) throws -> ResolvedBase? {
        if noBase { return nil }

        // Explicit --base
        if let explicit = base {
            let parentTask = try StateManager.find(repo: repo, branchOrSlug: explicit)
            return ResolvedBase(branch: explicit, parentTask: parentTask, autoDetected: false)
        }

        // Auto-detect: check if cwd is inside an xwt-managed worktree
        guard let cwdTopLevel = try? ConfigLoader.detectWorkingTreeRoot() else { return nil }
        let canonicalCwd = URL(fileURLWithPath: cwdTopLevel).standardized.path

        let allTasks = try StateManager.listAll(repo: repo)
        for task in allTasks {
            let canonicalTaskPath = URL(fileURLWithPath: task.worktreePath).standardized.path
            if canonicalCwd == canonicalTaskPath {
                return ResolvedBase(branch: task.branch, parentTask: task, autoDetected: true)
            }
        }

        return nil
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
            "CLAUDE.local.md",
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
