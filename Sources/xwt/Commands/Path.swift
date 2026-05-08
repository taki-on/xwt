import ArgumentParser
import Foundation

struct Path: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Print the worktree path for a branch (use with `cd \"$(xwt path …)\"`).",
        discussion: """
        Prints the absolute worktree path on stdout. Errors go to stderr,
        so it's safe inside a command substitution like:

          cd "$(xwt path feature/login)"

        When run inside a repo, looks up the task in that repo. Otherwise
        scans all repos under ~/.xwt/repos and resolves to a single match.
        Use --repo to disambiguate when the same branch exists in multiple
        repos.
        """
    )

    @Argument(help: "Branch name or slug.")
    var branch: String

    @Option(name: .shortAndLong, help: "Constrain lookup to this repo.")
    var repo: String?

    func run() throws {
        let task = try resolveTask()
        Terminal.out(task.worktreePath)
    }

    private func resolveTask() throws -> TaskState {
        if let repo {
            if let task = try StateManager.find(repo: repo, branchOrSlug: branch) {
                return task
            }
            Terminal.errorLine("no task found for '\(branch)' in repo '\(repo)'")
            throw ExitCode.failure
        }

        // Try the cwd's repo first — it's almost always what the user wants.
        if let mainRoot = try? ConfigLoader.detectMainRepoRoot() {
            let repoName = ConfigLoader.repoName(from: mainRoot)
            if let task = try StateManager.find(repo: repoName, branchOrSlug: branch) {
                return task
            }
        }

        // Fall back to scanning all known repos.
        let allRepos = try StateManager.listAllRepos()
        var matches: [(repo: String, task: TaskState)] = []
        for r in allRepos {
            if let task = try StateManager.find(repo: r, branchOrSlug: branch) {
                matches.append((r, task))
            }
        }
        if matches.count == 1 {
            return matches[0].task
        }
        if matches.count > 1 {
            let repos = matches.map(\.repo).joined(separator: ", ")
            Terminal.errorLine("branch '\(branch)' matches tasks in multiple repos (\(repos)) — pass --repo to disambiguate")
            throw ExitCode.failure
        }
        Terminal.errorLine("no task found for '\(branch)'")
        throw ExitCode.failure
    }
}
