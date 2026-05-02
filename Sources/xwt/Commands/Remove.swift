import ArgumentParser
import Foundation

struct Remove: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Remove a task: shutdown/delete simulator, remove worktree, clean up state."
    )

    @Argument(help: "Branch name or slug.")
    var branch: String

    @Flag(name: .long, help: "Keep the simulator device instead of deleting it.")
    var keepSimulator = false

    @Flag(name: .long, help: "Keep derived data instead of removing it.")
    var keepDerivedData = false

    @Flag(name: .shortAndLong, help: "Skip confirmation prompt.")
    var force = false

    @Flag(name: .long, help: "Re-point child tasks to this task's parent before removing.")
    var reparent = false

    @Flag(name: .long, help: "Remove this task and all its descendants.")
    var cascade = false

    func run() throws {
        let repoRoot = try ConfigLoader.detectMainRepoRoot()
        let repo = ConfigLoader.repoName(from: repoRoot)

        guard let task = try StateManager.find(repo: repo, branchOrSlug: branch) else {
            print("❌ No task found for '\(branch)'.")
            throw ExitCode.failure
        }

        let children = try StateManager.findChildren(repo: repo, slug: task.slug)

        // Warn about children if neither --reparent nor --cascade
        if !children.isEmpty && !reparent && !cascade {
            print("⚠ Task '\(task.branch)' has \(children.count) child branch\(children.count == 1 ? "" : "es"):")
            for child in children {
                print("  • \(child.branch)")
            }
            print()
            print("Use --reparent to re-point children to '\(task.parentBranch ?? "root")',")
            print("or --cascade to remove this task and all descendants.")
            throw ExitCode.failure
        }

        // Load all tasks once for shared-resource detection
        let allTasks = try StateManager.listAll(repo: repo)

        if cascade {
            let descendants = try StateManager.findDescendants(repo: repo, slug: task.slug)
            let allRemoving = [task] + descendants
            let removingSlugs = Set(allRemoving.map(\.slug))
            if !force {
                print("About to remove \(allRemoving.count) task(s):")
                for t in allRemoving { print("  • \(t.branch)") }
                print()
                print("Continue? [y/N] ", terminator: "")
                guard let answer = readLine()?.lowercased(), answer == "y" || answer == "yes" else {
                    print("Cancelled.")
                    return
                }
            }
            for t in allRemoving.reversed() {
                removeSingleTask(t, repoRoot: repoRoot, repo: repo, allTasks: allTasks, removingSlugs: removingSlugs)
            }
            print("✅ Removed \(allRemoving.count) task(s).")
            return
        }

        if reparent && !children.isEmpty {
            print("🔄 Re-parenting \(children.count) child branch\(children.count == 1 ? "" : "es")...")
            for child in children {
                let updated = TaskState(
                    repo: child.repo,
                    branch: child.branch,
                    slug: child.slug,
                    worktreePath: child.worktreePath,
                    simulatorName: child.simulatorName,
                    simulatorUDID: child.simulatorUDID,
                    derivedDataPath: child.derivedDataPath,
                    scheme: child.scheme,
                    workspace: child.workspace,
                    project: child.project,
                    package: child.package,
                    createdAt: child.createdAt,
                    parentBranch: task.parentBranch,
                    parentSlug: task.parentSlug
                )
                try StateManager.save(updated)
                print("   ↳ \(child.branch) → base: \(task.parentBranch ?? "root")")
            }
        }

        // Determine what will happen with simulator/derived data for the confirmation prompt
        let removingSlugs: Set<String> = [task.slug]
        let simShared = isSimulatorShared(task: task, allTasks: allTasks, removingSlugs: removingSlugs)
        let ddShared = isDerivedDataShared(task: task, allTasks: allTasks, removingSlugs: removingSlugs)

        if !force {
            print("About to remove task for '\(task.branch)':")
            print("  Worktree:    \(task.worktreePath)")
            print("  Simulator:   \(task.simulatorName) (\(task.simulatorUDID.prefix(8))…)")
            if simShared {
                print("  ℹ Will keep simulator — still used by other tasks")
            } else if keepSimulator {
                print("  ℹ Will only shutdown simulator (--keep-simulator)")
            } else {
                print("  🗑 Will DELETE simulator")
            }
            if ddShared {
                print("  ℹ Will keep derived data — still used by other tasks")
            } else if keepDerivedData {
                print("  ℹ Will keep derived data (--keep-derived-data)")
            } else {
                print("  🧹 Will remove derived data at \(task.derivedDataPath)")
            }
            print()
            print("Continue? [y/N] ", terminator: "")
            guard let answer = readLine()?.lowercased(), answer == "y" || answer == "yes" else {
                print("Cancelled.")
                return
            }
        }

        removeSingleTask(task, repoRoot: repoRoot, repo: repo, allTasks: allTasks, removingSlugs: removingSlugs)
    }

    /// Check if any task outside the removal set shares this task's simulator.
    private func isSimulatorShared(task: TaskState, allTasks: [TaskState], removingSlugs: Set<String>) -> Bool {
        allTasks.contains { $0.slug != task.slug && !removingSlugs.contains($0.slug) && $0.simulatorUDID == task.simulatorUDID }
    }

    /// Check if any task outside the removal set shares this task's derived data.
    private func isDerivedDataShared(task: TaskState, allTasks: [TaskState], removingSlugs: Set<String>) -> Bool {
        allTasks.contains { $0.slug != task.slug && !removingSlugs.contains($0.slug) && $0.derivedDataPath == task.derivedDataPath }
    }

    private func removeSingleTask(_ task: TaskState, repoRoot: String, repo: String, allTasks: [TaskState], removingSlugs: Set<String>) {
        let simShared = isSimulatorShared(task: task, allTasks: allTasks, removingSlugs: removingSlugs)
        let ddShared = isDerivedDataShared(task: task, allTasks: allTasks, removingSlugs: removingSlugs)

        var warnings: [String] = []

        if simShared {
            print("ℹ Keeping simulator '\(task.simulatorName)' — still used by other tasks.")
        } else {
            print("📱 Shutting down simulator '\(task.simulatorName)'...")
            try? SimulatorService.shutdown(udid: task.simulatorUDID)

            if !keepSimulator {
                print("🗑  Deleting simulator...")
                do {
                    try SimulatorService.delete(udid: task.simulatorUDID)
                } catch {
                    warnings.append("Could not delete simulator \(task.simulatorUDID): \(error)")
                }
            }
        }

        print("📂 Removing worktree...")
        do {
            try WorktreeService.remove(repoRoot: repoRoot, path: task.worktreePath)
        } catch {
            warnings.append("Could not remove worktree at \(task.worktreePath): \(error)")
        }

        if ddShared {
            print("ℹ Keeping derived data — still used by other tasks.")
        } else if !keepDerivedData {
            print("🧹 Cleaning derived data...")
            do {
                try FileManager.default.removeItem(atPath: task.derivedDataPath)
            } catch {
                warnings.append("Could not remove derived data at \(task.derivedDataPath): \(error)")
            }
        }

        try? StateManager.delete(repo: repo, slug: task.slug)

        if warnings.isEmpty {
            print("✅ Task '\(task.branch)' removed.")
        } else {
            print("⚠ Task '\(task.branch)' removed with warnings:")
            for warning in warnings {
                print("  • \(warning)")
            }
        }
    }
}
