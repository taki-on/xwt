import ArgumentParser
import Foundation

struct Run: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Build and run on the assigned simulator."
    )

    @Argument(help: "Branch name or slug.")
    var branch: String

    @Option(name: .shortAndLong, help: "Override the scheme to build.")
    var scheme: String?

    @Flag(name: .long, help: "Build only, don't install and launch.")
    var buildOnly = false

    func run() throws {
        let repoRoot = try ConfigLoader.detectRepoRoot()
        let repo = ConfigLoader.repoName(from: repoRoot)

        guard let task = try StateManager.find(repo: repo, branchOrSlug: branch) else {
            print("❌ No task found for '\(branch)'. Run 'simi start \(branch)' first.")
            throw ExitCode.failure
        }

        let buildScheme = scheme ?? task.scheme
        guard let buildScheme else {
            print("❌ No scheme configured. Set 'scheme' in .simi.json or pass --scheme.")
            throw ExitCode.failure
        }

        var args = ["xcodebuild"]

        if let workspace = task.workspace {
            args += ["-workspace", workspace]
        } else if let project = task.project {
            args += ["-project", project]
        }

        args += [
            "-scheme", buildScheme,
            "-destination", "id=\(task.simulatorUDID)",
            "-derivedDataPath", task.derivedDataPath,
        ]

        if buildOnly {
            args += ["build"]
        } else {
            args += ["build"]
        }

        print("🔨 Building \(buildScheme) for simulator \(task.simulatorName)...")
        print("   DerivedData: \(task.derivedDataPath)")
        print("   Destination: \(task.simulatorUDID)")
        print()

        try ShellRunner.exec(args)

        if !buildOnly {
            print("\n✅ Build succeeded.")
        }
    }
}
