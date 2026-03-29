import ArgumentParser
import Foundation

struct Shell: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Open a shell in the worktree for a task."
    )

    @Argument(help: "Branch name or slug.")
    var branch: String

    func run() throws {
        let repoRoot = try ConfigLoader.detectRepoRoot()
        let repo = ConfigLoader.repoName(from: repoRoot)

        guard let task = try StateManager.find(repo: repo, branchOrSlug: branch) else {
            print("❌ No task found for '\(branch)'. Run 'simi start \(branch)' first.")
            throw ExitCode.failure
        }

        guard FileManager.default.fileExists(atPath: task.worktreePath) else {
            print("❌ Worktree not found at \(task.worktreePath)")
            throw ExitCode.failure
        }

        print("🐚 Launching shell in \(task.worktreePath)")
        print("   Tip: run 'source .simi-context' to load environment variables.\n")

        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-i"]
        process.currentDirectoryURL = URL(fileURLWithPath: task.worktreePath)
        process.environment = ProcessInfo.processInfo.environment
        process.standardInput = FileHandle.standardInput
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError

        try process.run()
        process.waitUntilExit()
    }
}
