import ArgumentParser
import Foundation

struct List: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List all active tasks."
    )

    @Option(name: .shortAndLong, help: "Filter by repo name.")
    var repo: String?

    func run() throws {
        let repos: [String]
        if let repo {
            repos = [repo]
        } else {
            repos = try StateManager.listAllRepos()
        }

        guard !repos.isEmpty else {
            print("No active tasks.")
            return
        }

        // Fetch simulator state once for all tasks
        let allDevices = try SimulatorService.fetchAllDevices()

        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short

        var totalTasks = 0

        for repoName in repos.sorted() {
            let tasks = try StateManager.listAll(repo: repoName)
            guard !tasks.isEmpty else { continue }
            totalTasks += tasks.count

            print("📦 \(repoName)")
            print(String(repeating: "─", count: 80))

            for task in tasks.sorted(by: { $0.createdAt < $1.createdAt }) {
                let bootedStatus: String
                if let info = SimulatorService.findByUDID(task.simulatorUDID, in: allDevices) {
                    bootedStatus = info.isBooted ? "🟢 Booted" : "⚪ Shutdown"
                } else {
                    bootedStatus = "❌ Not found"
                }

                let dateStr = formatter.string(from: task.createdAt)

                print("  \(task.branch)")
                print("    Worktree:   \(task.worktreePath)")
                print("    Simulator:  \(task.simulatorName) (\(task.simulatorUDID.prefix(8))…) \(bootedStatus)")
                print("    Created:    \(dateStr)")
                print()
            }
        }

        if totalTasks == 0 {
            print("No active tasks.")
        }
    }
}
