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

        if cascade {
            let descendants = try StateManager.findDescendants(repo: repo, slug: task.slug)
            let allTasks = [task] + descendants
            if !force {
                print("About to remove \(allTasks.count) task(s):")
                for t in allTasks { print("  • \(t.branch)") }
                print()
                print("Continue? [y/N] ", terminator: "")
                guard let answer = readLine()?.lowercased(), answer == "y" || answer == "yes" else {
                    print("Cancelled.")
                    return
                }
            }
            for t in allTasks.reversed() {
                removeSingleTask(t, repoRoot: repoRoot, repo: repo)
            }
            print("✅ Removed \(allTasks.count) task(s).")
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

        if !force {
            print("About to remove task for '\(task.branch)':")
            print("  Worktree:    \(task.worktreePath)")
            print("  Simulator:   \(task.simulatorName) (\(task.simulatorUDID.prefix(8))…)")
            if !keepSimulator { print("  🗑 Will DELETE simulator") }
            if !keepDerivedData { print("  🧹 Will remove derived data at \(task.derivedDataPath)") }
            if keepSimulator { print("  ℹ Will only shutdown simulator (--keep-simulator)") }
            if keepDerivedData { print("  ℹ Will keep derived data (--keep-derived-data)") }
            print()
            print("Continue? [y/N] ", terminator: "")
            guard let answer = readLine()?.lowercased(), answer == "y" || answer == "yes" else {
                print("Cancelled.")
                return
            }
        }

        removeSingleTask(task, repoRoot: repoRoot, repo: repo)
    }

    private func removeSingleTask(_ task: TaskState, repoRoot: String, repo: String) {
        print("📱 Shutting down simulator '\(task.simulatorName)'...")
        try? SimulatorService.shutdown(udid: task.simulatorUDID)

        var warnings: [String] = []

        if !keepSimulator {
            print("🗑  Deleting simulator...")
            do {
                try SimulatorService.delete(udid: task.simulatorUDID)
            } catch {
                warnings.append("Could not delete simulator \(task.simulatorUDID): \(error)")
            }
        }

        print("📂 Removing worktree...")
        do {
            try WorktreeService.remove(repoRoot: repoRoot, path: task.worktreePath)
        } catch {
            warnings.append("Could not remove worktree at \(task.worktreePath): \(error)")
        }

        if !keepDerivedData {
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
