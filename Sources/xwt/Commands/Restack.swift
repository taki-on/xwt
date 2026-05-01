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
                print("❌ No task found for '\(branch)'.")
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
            print("No stacked branches to restack.")
            return
        }

        // Preflight: validate all worktrees exist and are clean
        for task in tasksToRestack {
            guard FileManager.default.fileExists(atPath: task.worktreePath) else {
                print("❌ Worktree missing for '\(task.branch)' at \(task.worktreePath)")
                print("   Cannot restack. Remove and recreate the task first.")
                throw ExitCode.failure
            }
            let status = try ShellRunner.run("git", "-C", task.worktreePath, "status", "--porcelain")
            if !status.isEmpty {
                print("❌ Worktree for '\(task.branch)' has uncommitted changes:")
                print("   \(task.worktreePath)")
                print("   Commit or stash changes before restacking.")
                throw ExitCode.failure
            }
        }

        print("🔄 Restacking \(tasksToRestack.count) branch\(tasksToRestack.count == 1 ? "" : "es")...\n")

        for task in tasksToRestack {
            guard let parentBranch = task.parentBranch else { continue }
            print("  ↻ Rebasing '\(task.branch)' onto '\(parentBranch)'...")

            do {
                try ShellRunner.run("git", "-C", task.worktreePath, "rebase", parentBranch)
                print("    ✓ Done")
            } catch {
                print("    ❌ Rebase conflict!")
                print("    Resolve conflicts in: \(task.worktreePath)")
                print("    Then run: git -C \(task.worktreePath) rebase --continue")
                print("    And re-run: xwt restack \(task.branch)")
                throw ExitCode.failure
            }
        }

        print("\n✅ Restack complete.")
    }
}
