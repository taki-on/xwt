import ArgumentParser
import Foundation

struct Restack: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Rebase stacked branches onto their updated parents."
    )

    @Argument(help: "Branch name or slug to restack from. Omit to restack all stacked branches.")
    var branch: String?

    func run() throws {
        let repoRoot = try ConfigLoader.detectMainRepoRoot()
        let repo = ConfigLoader.repoName(from: repoRoot)

        let tasksToRestack: [TaskState]

        if let branch {
            guard let task = try StateManager.find(repo: repo, branchOrSlug: branch) else {
                Terminal.errorLine("no task found for '\(branch)'")
                throw ExitCode.failure
            }
            let descendants = try StateManager.findDescendants(repo: repo, slug: task.slug)
            tasksToRestack = StateManager.topologicalSort([task] + descendants)
                .filter { $0.parentSlug != nil }
        } else {
            // Restack all stacked branches in the repo
            let allTasks = try StateManager.listAll(repo: repo)
            tasksToRestack = StateManager.topologicalSort(allTasks)
                .filter { $0.parentSlug != nil }
        }

        guard !tasksToRestack.isEmpty else {
            Terminal.out("No stacked branches to restack.")
            return
        }

        // Preflight: validate all worktrees exist and are clean
        for task in tasksToRestack {
            guard FileManager.default.fileExists(atPath: task.worktreePath) else {
                Terminal.errorLine("worktree missing for '\(task.branch)' at \(task.worktreePath) — cannot restack; remove and recreate the task first")
                throw ExitCode.failure
            }
            let status = try ShellRunner.run("git", "-C", task.worktreePath, "status", "--porcelain")
            if !status.isEmpty {
                Terminal.errorLine("worktree for '\(task.branch)' has uncommitted changes at \(task.worktreePath) — commit or stash before restacking")
                throw ExitCode.failure
            }
        }

        let count = tasksToRestack.count
        Terminal.out(.heading, "Restacking \(count) branch\(count == 1 ? "" : "es")")
        Terminal.out()

        for task in tasksToRestack {
            guard let parentBranch = task.parentBranch else { continue }
            do {
                try Spinner.around(
                    "Rebasing '\(task.branch)' onto '\(parentBranch)'",
                    final: "Rebased '\(task.branch)' onto '\(parentBranch)'"
                ) {
                    try ShellRunner.run("git", "-C", task.worktreePath, "rebase", parentBranch)
                }
            } catch {
                Terminal.errorLine("rebase conflict in \(task.worktreePath)")
                Terminal.err(.muted, "    Resolve conflicts, then run:")
                Terminal.err(.muted, "      git -C \(task.worktreePath) rebase --continue")
                Terminal.err(.muted, "      xwt restack \(task.branch)")
                throw ExitCode.failure
            }
        }

        Terminal.out()
        Terminal.out(.success, "  ✓ Restack complete")
    }
}
