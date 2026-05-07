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
            Terminal.errorLine("no task found for '\(branch)'")
            throw ExitCode.failure
        }

        let children = try StateManager.findChildren(repo: repo, slug: task.slug)

        // Warn about children if neither --reparent nor --cascade
        if !children.isEmpty && !reparent && !cascade {
            Terminal.errorLine("task '\(task.branch)' has \(children.count) child branch\(children.count == 1 ? "" : "es"):")
            for child in children {
                Terminal.err(.muted, "  • \(child.branch)")
            }
            Terminal.err("")
            Terminal.err(.muted, "Use --reparent to re-point children to '\(task.parentBranch ?? "root")',")
            Terminal.err(.muted, "or --cascade to remove this task and all descendants.")
            throw ExitCode.failure
        }

        // Load all tasks once for shared-resource detection
        let allTasks = try StateManager.listAll(repo: repo)

        if cascade {
            let descendants = try StateManager.findDescendants(repo: repo, slug: task.slug)
            let allRemoving = [task] + descendants
            let removingSlugs = Set(allRemoving.map(\.slug))
            if !force {
                Terminal.out(.heading, "About to remove \(allRemoving.count) task(s):")
                for t in allRemoving { Terminal.out("  • \(t.branch)") }
                Terminal.out()
                if !confirm("Continue?") {
                    Terminal.out("Cancelled.")
                    return
                }
            }
            for t in allRemoving.reversed() {
                removeSingleTask(t, repoRoot: repoRoot, repo: repo, allTasks: allTasks, removingSlugs: removingSlugs)
            }
            Terminal.out()
            Terminal.out(.success, "  ✓ Removed \(allRemoving.count) task(s)")
            return
        }

        if reparent && !children.isEmpty {
            Terminal.out(.info, "  › Re-parenting \(children.count) child branch\(children.count == 1 ? "" : "es")…")
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
                Terminal.out(.muted, "    ↳ \(child.branch) → base: \(task.parentBranch ?? "root")")
            }
        }

        // Determine what will happen with simulator/derived data for the confirmation prompt
        let removingSlugs: Set<String> = [task.slug]
        let simShared = isSimulatorShared(task: task, allTasks: allTasks, removingSlugs: removingSlugs)
        let ddShared = isDerivedDataShared(task: task, allTasks: allTasks, removingSlugs: removingSlugs)

        if !force {
            Terminal.out(.heading, "About to remove task for '\(task.branch)':")
            Terminal.out("  Worktree:    \(task.worktreePath)")
            Terminal.out("  Simulator:   \(task.simulatorName) (\(task.simulatorUDID.prefix(8))…)")
            if simShared {
                Terminal.out(.muted, "    will keep simulator — still used by other tasks")
            } else if keepSimulator {
                Terminal.out(.muted, "    will only shutdown simulator (--keep-simulator)")
            } else {
                Terminal.out(.muted, "    will DELETE simulator")
            }
            if ddShared {
                Terminal.out(.muted, "    will keep derived data — still used by other tasks")
            } else if keepDerivedData {
                Terminal.out(.muted, "    will keep derived data (--keep-derived-data)")
            } else {
                Terminal.out(.muted, "    will remove derived data at \(task.derivedDataPath)")
            }
            Terminal.out()
            if !confirm("Continue?") {
                Terminal.out("Cancelled.")
                return
            }
        }

        removeSingleTask(task, repoRoot: repoRoot, repo: repo, allTasks: allTasks, removingSlugs: removingSlugs)
    }

    /// Read a yes/no answer from stdin. Default is "no" — only `y` / `yes`
    /// (case-insensitive) confirms.
    private func confirm(_ prompt: String) -> Bool {
        Terminal.write("\(prompt) [y/N] ")
        guard let answer = readLine()?.trimmingCharacters(in: .whitespaces).lowercased() else {
            return false
        }
        return answer == "y" || answer == "yes"
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
            Terminal.out(.muted, "  · keeping simulator '\(task.simulatorName)' — still used by other tasks")
        } else {
            do {
                try Spinner.around(
                    "Shutting down simulator '\(task.simulatorName)'",
                    final: "Simulator '\(task.simulatorName)' shut down"
                ) {
                    try SimulatorService.shutdown(udid: task.simulatorUDID)
                }
            } catch {
                // shutdown is already best-effort; ignore
            }

            if !keepSimulator {
                do {
                    try Spinner.around("Deleting simulator", final: "Simulator deleted") {
                        try SimulatorService.delete(udid: task.simulatorUDID)
                    }
                } catch {
                    warnings.append("could not delete simulator \(task.simulatorUDID): \(error)")
                }
            }
        }

        do {
            try Spinner.around("Removing worktree", final: "Worktree removed") {
                try WorktreeService.remove(repoRoot: repoRoot, path: task.worktreePath)
            }
        } catch {
            warnings.append("could not remove worktree at \(task.worktreePath): \(error)")
        }

        if ddShared {
            Terminal.out(.muted, "  · keeping derived data — still used by other tasks")
        } else if !keepDerivedData {
            do {
                try Spinner.around("Cleaning derived data", final: "Derived data cleaned") {
                    try FileManager.default.removeItem(atPath: task.derivedDataPath)
                }
            } catch {
                warnings.append("could not remove derived data at \(task.derivedDataPath): \(error)")
            }
        }

        try? StateManager.delete(repo: repo, slug: task.slug)

        if warnings.isEmpty {
            Terminal.out(.success, "  ✓ Task '\(task.branch)' removed")
        } else {
            Terminal.warningLine("task '\(task.branch)' removed with warnings:")
            for warning in warnings {
                Terminal.err(.muted, "  • \(warning)")
            }
        }
    }
}
