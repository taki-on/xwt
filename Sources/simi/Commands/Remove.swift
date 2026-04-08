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

    func run() throws {
        let repoRoot = try ConfigLoader.detectRepoRoot()
        let repo = ConfigLoader.repoName(from: repoRoot)

        guard let task = try StateManager.find(repo: repo, branchOrSlug: branch) else {
            print("❌ No task found for '\(branch)'.")
            throw ExitCode.failure
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

        // 1. Shutdown simulator
        print("📱 Shutting down simulator...")
        try SimulatorService.shutdown(udid: task.simulatorUDID)

        var warnings: [String] = []

        // 2. Delete simulator (default) or keep it
        if !keepSimulator {
            print("🗑  Deleting simulator...")
            do {
                try SimulatorService.delete(udid: task.simulatorUDID)
            } catch {
                warnings.append("Could not delete simulator \(task.simulatorUDID): \(error)")
            }
        }

        // 3. Remove worktree
        print("📂 Removing worktree...")
        do {
            try WorktreeService.remove(repoRoot: repoRoot, path: task.worktreePath)
        } catch {
            warnings.append("Could not remove worktree at \(task.worktreePath): \(error)")
        }

        // 4. Clean derived data (default) or keep it
        if !keepDerivedData {
            print("🧹 Cleaning derived data...")
            do {
                try FileManager.default.removeItem(atPath: task.derivedDataPath)
            } catch {
                warnings.append("Could not remove derived data at \(task.derivedDataPath): \(error)")
            }
        }

        // 5. Remove state file
        try StateManager.delete(repo: repo, slug: task.slug)

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
