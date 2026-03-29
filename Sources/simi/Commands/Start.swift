import ArgumentParser
import Foundation

struct Start: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Start a new task: create worktree, assign simulator, generate .simi-context."
    )

    @Argument(help: "Branch name (e.g. feature/login-refactor).")
    var branch: String

    @Option(name: .shortAndLong, help: "Device type (e.g. 'iPhone 16 Pro Max'). Overrides .simi.json.")
    var device: String?

    @Option(name: .shortAndLong, help: "iOS runtime (e.g. 'iOS 18.0'). Overrides .simi.json.")
    var runtime: String?

    @Flag(name: .long, help: "Don't boot the simulator after creating it.")
    var noBoot = false

    func run() throws {
        let repoRoot = try ConfigLoader.detectRepoRoot()
        let repo = ConfigLoader.repoName(from: repoRoot)
        let slug = BranchSlug.slugify(branch)
        let config = try ConfigLoader.loadConfigWithDefaults(repoRoot: repoRoot)

        // Check for existing task
        if let existing = try StateManager.find(repo: repo, branchOrSlug: branch) {
            print("⚠ Task already exists for '\(existing.branch)'. Use 'simi remove \(branch)' first.")
            throw ExitCode.failure
        }

        let worktreePath = Paths.worktreePath(repo: repo, slug: slug).path
        let derivedDataPath = Paths.derivedDataPath(slug: slug).path
        let simName = "simi-\(slug)"

        // 1. Create worktree
        print("📂 Creating worktree at \(worktreePath)...")
        try WorktreeService.add(repoRoot: repoRoot, branch: branch, path: worktreePath)

        // 2. Create or reuse simulator (CLI flags override .simi.json)
        let deviceType = device ?? config.deviceType ?? "iPhone 17 Pro"
        let runtime = self.runtime ?? config.runtime ?? "iOS 26.3"
        print("📱 Setting up simulator '\(simName)' (\(deviceType), \(runtime))...")
        let (udid, reused) = try SimulatorService.createOrReuse(name: simName, deviceType: deviceType, runtime: runtime)
        print(reused ? "   ↳ Reusing existing simulator \(udid)" : "   ↳ Created new simulator \(udid)")

        // 3. Boot simulator
        if !noBoot {
            print("🚀 Booting simulator...")
            try SimulatorService.boot(udid: udid)
        }

        // 4. Create derived data directory
        try FileManager.default.createDirectory(atPath: derivedDataPath, withIntermediateDirectories: true)

        // 5. Save task state
        let task = TaskState(
            repo: repo,
            branch: branch,
            slug: slug,
            worktreePath: worktreePath,
            simulatorName: simName,
            simulatorUDID: udid,
            derivedDataPath: derivedDataPath,
            scheme: config.scheme,
            workspace: config.workspace,
            project: config.project,
            createdAt: Date()
        )
        try StateManager.save(task)

        // 6. Write .simi-context
        try StateManager.writeSimiContext(task)
        print("✅ Task started: \(branch)")
        print("   Worktree:     \(worktreePath)")
        print("   Simulator:    \(simName) (\(udid))")
        print("   DerivedData:  \(derivedDataPath)")
        print("")
        print("   cd \(worktreePath)")
        print("   source .simi-context")
        print("")
        print("   In Copilot CLI, say: \"configure XcodeBuildMCP from .simi-context\"")
    }
}
