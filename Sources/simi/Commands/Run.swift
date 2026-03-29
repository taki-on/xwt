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
            "build",
        ]

        print("🔨 Building \(buildScheme) for simulator \(task.simulatorName)...")
        print("   DerivedData: \(task.derivedDataPath)")
        print("   Destination: \(task.simulatorUDID)")
        print()

        try ShellRunner.exec(args)

        if buildOnly {
            print("\n✅ Build succeeded.")
            return
        }

        // Find, install, and launch the built app
        let appPath = try Run.findBuiltApp(derivedDataPath: task.derivedDataPath)
        let bundleID = try Run.readBundleID(appPath: appPath)

        print("\n📲 Installing \(bundleID) on \(task.simulatorName)...")
        try SimulatorService.install(udid: task.simulatorUDID, appPath: appPath)

        print("🚀 Launching \(bundleID)...")
        try SimulatorService.launch(udid: task.simulatorUDID, bundleID: bundleID)

        print("✅ Build, install, and launch succeeded.")
    }

    // MARK: - Helpers

    /// Find the .app bundle built for the simulator in DerivedData.
    private static func findBuiltApp(derivedDataPath: String) throws -> String {
        let productsDir = "\(derivedDataPath)/Build/Products"
        let output = try ShellRunner.run("find", productsDir, "-name", "*.app", "-type", "d", "-maxdepth", "3")
        let apps = output.components(separatedBy: "\n").filter { !$0.isEmpty }

        // Prefer simulator builds
        if let simApp = apps.first(where: { $0.contains("-iphonesimulator") }) {
            return simApp
        }
        guard let app = apps.first else {
            print("❌ No .app bundle found in \(productsDir).")
            throw ExitCode.failure
        }
        return app
    }

    /// Read CFBundleIdentifier from an app's Info.plist.
    private static func readBundleID(appPath: String) throws -> String {
        try ShellRunner.run(
            "/usr/libexec/PlistBuddy", "-c", "Print :CFBundleIdentifier",
            "\(appPath)/Info.plist"
        )
    }
}
