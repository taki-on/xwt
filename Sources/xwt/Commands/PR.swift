import ArgumentParser
import Foundation

struct PR: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Create a GitHub pull request with the correct base branch for stacked PRs."
    )

    @Argument(help: "Branch name or slug.")
    var branch: String

    @Flag(name: .long, help: "Create a draft pull request.")
    var draft = false

    @Option(name: .long, help: "Pull request title. If omitted, gh infers from commits.")
    var title: String?

    @Option(name: .long, help: "Pull request body.")
    var body: String?

    @Flag(name: .long, help: "Use first commit message as title and body.")
    var fill = false

    func run() throws {
        let repoRoot = try ConfigLoader.detectMainRepoRoot()
        let repo = ConfigLoader.repoName(from: repoRoot)

        guard let task = try StateManager.find(repo: repo, branchOrSlug: branch) else {
            Terminal.errorLine("no task found for '\(branch)' — run 'xwt start \(branch)' first")
            throw ExitCode.failure
        }

        // Determine base branch: parentBranch from state, or detect main branch
        let baseBranch = task.parentBranch ?? StateManager.detectMainBranch(repoRoot: repoRoot)

        // Push branch
        Terminal.out(.info, "  › Pushing '\(task.branch)' to remote…")
        do {
            try ShellRunner.run("git", "-C", task.worktreePath, "push", "-u", "origin", task.branch)
        } catch {
            Terminal.warningLine("push failed (\(error)) — continuing with PR creation; branch may already be pushed")
        }

        // Build gh pr create arguments
        var args = ["gh", "pr", "create", "--base", baseBranch, "--head", task.branch]

        if draft { args.append("--draft") }
        if fill { args.append("--fill") }
        if let title { args += ["--title", title] }
        if let body { args += ["--body", body] }
        if !fill && title == nil { args.append("--fill") }

        Terminal.out(.info, "  › Creating PR: \(task.branch) → \(baseBranch)")
        if task.parentBranch != nil {
            Terminal.out(.muted, "    ↳ stacked PR (base is parent branch, not main)")
        }

        // Run gh from the worktree so it picks up the correct repo
        try ShellRunner.exec(args, cwd: task.worktreePath)
    }
}
