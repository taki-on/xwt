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

            let hasStacks = tasks.contains { $0.parentSlug != nil }
            if hasStacks {
                printTree(tasks: tasks, devices: allDevices, formatter: formatter)
            } else {
                for task in tasks.sorted(by: { $0.createdAt < $1.createdAt }) {
                    printTaskFlat(task, devices: allDevices, formatter: formatter)
                }
            }
        }

        if totalTasks == 0 {
            print("No active tasks.")
        }
    }

    // MARK: - Tree rendering

    private func printTree(tasks: [TaskState], devices: [String: SimulatorInfo], formatter: DateFormatter) {
        let byParent = Dictionary(grouping: tasks, by: { $0.parentSlug ?? "" })
        let roots = tasks
            .filter { task in task.parentSlug == nil || !tasks.contains(where: { $0.slug == task.parentSlug }) }
            .sorted(by: { $0.createdAt < $1.createdAt })

        for (i, root) in roots.enumerated() {
            let isLast = i == roots.count - 1
            let prefix = isLast ? "  └── " : "  ├── "
            let childPrefix = isLast ? "      " : "  │   "
            printTaskNode(root, prefix: prefix, childPrefix: childPrefix, byParent: byParent, devices: devices, formatter: formatter)
        }
        print()
    }

    private func printTaskNode(
        _ task: TaskState,
        prefix: String,
        childPrefix: String,
        byParent: [String: [TaskState]],
        devices: [String: SimulatorInfo],
        formatter: DateFormatter
    ) {
        let status = simulatorStatus(task: task, devices: devices)
        print("\(prefix)\(task.branch) (\(task.simulatorName), \(status))")

        let children = (byParent[task.slug] ?? []).sorted(by: { $0.createdAt < $1.createdAt })
        for (j, child) in children.enumerated() {
            let isLastChild = j == children.count - 1
            let nextPrefix = childPrefix + (isLastChild ? "└── " : "├── ")
            let nextChildPrefix = childPrefix + (isLastChild ? "    " : "│   ")
            printTaskNode(child, prefix: nextPrefix, childPrefix: nextChildPrefix, byParent: byParent, devices: devices, formatter: formatter)
        }
    }

    // MARK: - Flat rendering

    private func printTaskFlat(_ task: TaskState, devices: [String: SimulatorInfo], formatter: DateFormatter) {
        let bootedStatus = simulatorStatus(task: task, devices: devices)
        let dateStr = formatter.string(from: task.createdAt)

        print("  \(task.branch)")
        print("    Worktree:   \(task.worktreePath)")
        print("    Simulator:  \(task.simulatorName) (\(task.simulatorUDID.prefix(8))…) \(bootedStatus)")
        print("    Created:    \(dateStr)")
        if let parent = task.parentBranch {
            print("    Base:       \(parent)")
        }
        print()
    }

    private func simulatorStatus(task: TaskState, devices: [String: SimulatorInfo]) -> String {
        if let info = SimulatorService.findByUDID(task.simulatorUDID, in: devices) {
            return info.isBooted ? "🟢 Booted" : "⚪ Shutdown"
        }
        return "❌ Not found"
    }
}
