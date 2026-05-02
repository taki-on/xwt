import ArgumentParser
import Foundation

struct Init: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "init",
        abstract: "Interactively create or update .xwt.json configuration."
    )

    func run() throws {
        let repoRoot = try ConfigLoader.detectMainRepoRoot()
        let repo = ConfigLoader.repoName(from: repoRoot)

        print("🚀 Initializing xwt for '\(repo)'\n")

        // Load existing config as defaults
        var config: RepoConfig
        do {
            if let existing = try RepoConfig.load(from: repoRoot) {
                config = existing
            } else {
                config = RepoConfig()
            }
        } catch {
            print("⚠ Existing .xwt.json could not be parsed: \(error)")
            print("  Starting with empty defaults.\n")
            config = RepoConfig()
        }

        // 1. Workspace / Project
        config = try configureWorkspaceOrProject(repoRoot: repoRoot, config: config)

        // 2. Scheme
        config = try configureScheme(repoRoot: repoRoot, config: config)

        // 3. Device type
        config = try configureDeviceType(config: config)

        // 4. Runtime
        config = try configureRuntime(config: config)

        // 5. Source simulator
        config = try configureSourceSimulator(config: config)

        // 6. Worktree directory
        config = configureWorktreeDir(config: config)

        // 7. AI agents
        config = configureAgents(config: config)

        // Write config
        print()
        try config.save(to: repoRoot)

        let configPath = URL(fileURLWithPath: repoRoot)
            .appendingPathComponent(RepoConfig.fileName).path
        print("✅ Configuration saved to \(configPath)\n")

        // 7. Git exclusions
        configureGitExclusions(repoRoot: repoRoot)

        printSummary(config)
    }

    // MARK: - Step 1: Workspace / Project

    private func configureWorkspaceOrProject(
        repoRoot: String,
        config: RepoConfig
    ) throws -> RepoConfig {
        var config = config
        let repoURL = URL(fileURLWithPath: repoRoot)
        let contents = try FileManager.default.contentsOfDirectory(
            at: repoURL, includingPropertiesForKeys: nil
        )

        var options: [String] = []
        for url in contents.sorted(by: { $0.path < $1.path }) {
            let name = url.lastPathComponent
            if name.hasSuffix(".xcworkspace") && !name.hasPrefix(".") {
                options.append(name)
            } else if name.hasSuffix(".xcodeproj") {
                options.append(name)
            } else if name == "Package.swift" {
                options.append(name)
            }
        }

        let currentValue = config.workspace ?? config.project ?? config.package
        let defaultIndex = currentValue.flatMap { cv in options.firstIndex(of: cv) }

        let selected: String?
        if options.isEmpty {
            selected = Prompt.input(
                prompt: "📦 Workspace, project, or Package.swift path (or press Enter to skip)",
                defaultValue: currentValue
            )
        } else {
            selected = Prompt.choose(
                prompt: "📦 Select workspace, project, or Swift Package:",
                options: options,
                defaultIndex: defaultIndex,
                allowNone: true
            )
        }

        // Clear all three, then set the appropriate one
        config.workspace = nil
        config.project = nil
        config.package = nil
        if let selected {
            if selected.hasSuffix(".xcworkspace") {
                config.workspace = selected
            } else if selected.hasSuffix(".xcodeproj") {
                config.project = selected
            } else if selected == "Package.swift" || selected.hasSuffix("/Package.swift") {
                config.package = selected
            } else {
                // Fallback for free-form input that doesn't match a known suffix:
                // treat as a project path.
                config.project = selected
            }
        }

        print()
        return config
    }

    // MARK: - Step 2: Scheme

    private func configureScheme(
        repoRoot: String,
        config: RepoConfig
    ) throws -> RepoConfig {
        var config = config
        var schemes: [String] = []

        if let workspace = config.workspace {
            schemes = detectSchemes(flag: "-workspace", value: workspace, repoRoot: repoRoot)
        } else if let project = config.project {
            schemes = detectSchemes(flag: "-project", value: project, repoRoot: repoRoot)
        } else if config.package != nil {
            schemes = detectPackageSchemes(repoRoot: repoRoot)
        }

        if !schemes.isEmpty {
            let defaultIndex = config.scheme.flatMap { schemes.firstIndex(of: $0) }
            let selected = Prompt.choose(
                prompt: "🔧 Select scheme:",
                options: schemes,
                defaultIndex: defaultIndex,
                allowNone: true
            )
            config.scheme = selected
        } else {
            config.scheme = Prompt.input(
                prompt: "🔧 Scheme name (or press Enter to skip)",
                defaultValue: config.scheme
            )
        }

        print()
        return config
    }

    private func detectSchemes(flag: String, value: String, repoRoot: String) -> [String] {
        print("   Detecting schemes...")
        let absolutePath = URL(fileURLWithPath: repoRoot)
            .appendingPathComponent(value).path
        do {
            let output = try ShellRunner.run(
                "xcodebuild", flag, absolutePath, "-list"
            )
            return parseSchemes(from: output)
        } catch {
            print("   ⚠ Could not detect schemes: \(error)")
            return []
        }
    }

    private func detectPackageSchemes(repoRoot: String) -> [String] {
        print("   Detecting schemes...")
        do {
            let output = try ShellRunner.run(["xcodebuild", "-list"], cwd: repoRoot)
            return parseSchemes(from: output)
        } catch {
            print("   ⚠ Could not detect schemes: \(error)")
            return []
        }
    }

    private func parseSchemes(from output: String) -> [String] {
        let lines = output.components(separatedBy: .newlines)
        var inSchemes = false
        var schemes: [String] = []
        for line in lines {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("Schemes:") {
                inSchemes = true
                continue
            }
            if inSchemes {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty { break }
                schemes.append(trimmed)
            }
        }
        return schemes
    }

    // MARK: - Step 3: Device Type

    private func configureDeviceType(config: RepoConfig) throws -> RepoConfig {
        var config = config

        let deviceTypes: [DeviceTypeInfo]
        do {
            deviceTypes = try detectDeviceTypes()
        } catch {
            print("   ⚠ Could not detect device types: \(error)")
            config.deviceType = Prompt.input(
                prompt: "📱 Device type (e.g. 'iPhone 16 Pro')",
                defaultValue: config.deviceType ?? "iPhone 17 Pro"
            )
            print()
            return config
        }

        let names = deviceTypes.map(\.name)

        let defaultName = config.deviceType ?? "iPhone 17 Pro"
        let defaultIndex = names.firstIndex(of: defaultName)

        let selected = Prompt.choose(
            prompt: "📱 Select device type:",
            options: names,
            defaultIndex: defaultIndex
        )
        config.deviceType = selected

        print()
        return config
    }

    private struct DeviceTypeInfo {
        let name: String
        let identifier: String
    }

    private struct DeviceTypeList: Decodable {
        let devicetypes: [DeviceType]
        struct DeviceType: Decodable {
            let name: String
            let identifier: String
        }
    }

    private func detectDeviceTypes() throws -> [DeviceTypeInfo] {
        let output = try ShellRunner.run("xcrun", "simctl", "list", "devicetypes", "--json")
        guard let data = output.data(using: .utf8) else { return [] }
        let list = try JSONDecoder().decode(DeviceTypeList.self, from: data)
        return list.devicetypes
            .filter { $0.name.contains("iPhone") }
            .map { DeviceTypeInfo(name: $0.name, identifier: $0.identifier) }
    }

    // MARK: - Step 4: Runtime

    private func configureRuntime(config: RepoConfig) throws -> RepoConfig {
        var config = config

        let runtimes: [RuntimeInfo]
        do {
            runtimes = try detectRuntimes()
        } catch {
            print("   ⚠ Could not detect runtimes: \(error)")
            config.runtime = Prompt.input(
                prompt: "🖥  iOS runtime (e.g. 'iOS 18.2')",
                defaultValue: config.runtime ?? "iOS 26.4"
            )
            print()
            return config
        }

        let names = runtimes.map(\.name)

        let defaultName = config.runtime ?? "iOS 26.4"
        let defaultIndex = names.firstIndex(of: defaultName)

        let selected = Prompt.choose(
            prompt: "🖥  Select iOS runtime:",
            options: names,
            defaultIndex: defaultIndex
        )
        config.runtime = selected

        print()
        return config
    }

    private struct RuntimeInfo {
        let name: String
        let identifier: String
    }

    private struct RuntimeList: Decodable {
        let runtimes: [Runtime]
        struct Runtime: Decodable {
            let name: String
            let identifier: String
            let isAvailable: Bool
        }
    }

    private func detectRuntimes() throws -> [RuntimeInfo] {
        let output = try ShellRunner.run("xcrun", "simctl", "list", "runtimes", "--json")
        guard let data = output.data(using: .utf8) else { return [] }
        let list = try JSONDecoder().decode(RuntimeList.self, from: data)
        return list.runtimes
            .filter { $0.isAvailable && $0.name.hasPrefix("iOS") }
            .map { RuntimeInfo(name: $0.name, identifier: $0.identifier) }
    }

    // MARK: - Step 5: Source Simulator

    private func configureSourceSimulator(config: RepoConfig) throws -> RepoConfig {
        var config = config

        let devices = try SimulatorService.fetchAllDevices()
        let sorted = devices.values
            .filter { !$0.name.hasPrefix("xwt-") }
            .sorted { $0.name < $1.name }

        let names = sorted.map {
            "\($0.name) — \($0.udid.prefix(8))… (\($0.isBooted ? "Booted" : "Shutdown"))"
        }
        let simNames = sorted.map(\.name)

        let defaultIndex = config.sourceSimulator.flatMap { src in
            sorted.firstIndex { $0.name == src || $0.udid == src }
        }

        let selected = Prompt.choose(
            prompt: "🔑 Copy keychain from simulator (for auto-login):",
            options: names,
            defaultIndex: defaultIndex,
            allowNone: true
        )

        if let selected, let idx = names.firstIndex(of: selected) {
            config.sourceSimulator = simNames[idx]
        } else {
            config.sourceSimulator = nil
        }

        print()
        return config
    }

    // MARK: - Step 6: Worktree Directory

    private func configureWorktreeDir(config: RepoConfig) -> RepoConfig {
        var config = config
        let defaultDir = config.worktreeDir ?? "~/worktrees"

        let value = Prompt.input(
            prompt: "📂 Worktree base directory",
            defaultValue: defaultDir
        )

        // Only store if it differs from the built-in default
        if let value, value != "~/worktrees" {
            config.worktreeDir = value
        } else {
            config.worktreeDir = nil
        }

        return config
    }

    // MARK: - Step 7: AI Agents

    private func configureAgents(config: RepoConfig) -> RepoConfig {
        var config = config
        let allAgents = ["copilot", "claude-code"]
        let labels = ["Copilot CLI", "Claude Code"]
        let current = config.agents ?? allAgents

        print("🤖 Which AI agents should xwt generate instruction files for?")
        print("  (Select all that apply)\n")

        var selected: [String] = []
        for (i, agent) in allAgents.enumerated() {
            let isDefault = current.contains(agent)
            let defaultLabel = isDefault ? " [Y/n]" : " [y/N]"
            print("  \(labels[i])?\(defaultLabel) ", terminator: "")
            let answer = readLine()?.trimmingCharacters(in: .whitespaces).lowercased() ?? ""
            if answer.isEmpty {
                if isDefault { selected.append(agent) }
            } else if answer == "y" || answer == "yes" {
                selected.append(agent)
            }
        }

        if selected.isEmpty {
            print("  ⚠ No agents selected — defaulting to all.")
            selected = allAgents
        }

        // Only store if not the default (both selected)
        if Set(selected) == Set(allAgents) {
            config.agents = nil
        } else {
            config.agents = selected
        }

        print()
        return config
    }

    // MARK: - Step 8: Git Exclusions

    private func configureGitExclusions(repoRoot: String) {
        let gitignoreURL = URL(fileURLWithPath: repoRoot).appendingPathComponent(".gitignore")
        let excludeURL = resolveGitExcludeURL(repoRoot: repoRoot)

        let files: [(pattern: String, label: String)] = [
            (".xwt.json", "project config — may contain machine-specific settings"),
            (
                ".github/instructions/xwt.instructions.md",
                "Copilot instructions auto-generated by `xwt start`"
            ),
            (
                "CLAUDE.local.md",
                "Claude Code instructions auto-generated by `xwt start`"
            ),
        ]

        for (pattern, label) in files {
            if isPatternPresent(pattern, in: gitignoreURL) {
                print("   ℹ \(pattern) already in .gitignore")
                continue
            }
            if let excludeURL, isPatternPresent(pattern, in: excludeURL) {
                print("   ℹ \(pattern) already in .git/info/exclude")
                continue
            }

            let selected = Prompt.choose(
                prompt: "🙈 Exclude \(pattern) from git?\n   \(label)",
                options: [
                    ".gitignore — shared with the team, versioned in the repo",
                    ".git/info/exclude — local to your machine, not versioned",
                ],
                allowNone: true
            )

            if let selected {
                if selected.hasPrefix(".gitignore") {
                    appendPatternToFile(pattern, fileURL: gitignoreURL)
                    print("   ↳ Added to .gitignore")
                } else if let excludeURL {
                    appendPatternToFile(pattern, fileURL: excludeURL)
                    print("   ↳ Added to .git/info/exclude")
                }
            }
            print()
        }
    }

    private func resolveGitExcludeURL(repoRoot: String) -> URL? {
        guard let commonDir = try? ShellRunner.run(
            "git", "-C", repoRoot, "rev-parse", "--git-common-dir"
        ) else {
            return nil
        }
        let gitDirURL: URL
        if commonDir.hasPrefix("/") {
            gitDirURL = URL(fileURLWithPath: commonDir)
        } else {
            gitDirURL = URL(fileURLWithPath: repoRoot).appendingPathComponent(commonDir)
        }
        let url = gitDirURL.appendingPathComponent("info/exclude")
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        return url
    }

    private func isPatternPresent(_ pattern: String, in fileURL: URL) -> Bool {
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return false
        }
        let lines = content.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        return lines.contains(pattern)
    }

    private func appendPatternToFile(_ pattern: String, fileURL: URL) {
        do {
            var content = ""
            if FileManager.default.fileExists(atPath: fileURL.path) {
                content = try String(contentsOf: fileURL, encoding: .utf8)
            }
            if !content.isEmpty && !content.hasSuffix("\n") {
                content += "\n"
            }
            content += pattern + "\n"
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            print("   ⚠ Could not update \(fileURL.lastPathComponent): \(error.localizedDescription)")
        }
    }

    // MARK: - Summary

    private func printSummary(_ config: RepoConfig) {
        print("\n   Summary:")
        if let w = config.workspace { print("   workspace:        \(w)") }
        if let p = config.project { print("   project:          \(p)") }
        if let pkg = config.package { print("   package:          \(pkg)") }
        if let s = config.scheme { print("   scheme:           \(s)") }
        if let d = config.deviceType { print("   deviceType:       \(d)") }
        if let r = config.runtime { print("   runtime:          \(r)") }
        if let s = config.sourceSimulator { print("   sourceSimulator:  \(s)") }
        if let w = config.worktreeDir { print("   worktreeDir:      \(w)") }
        let agentNames = (config.agents ?? ["copilot", "claude-code"])
            .map { $0 == "copilot" ? "Copilot CLI" : "Claude Code" }
            .joined(separator: ", ")
        print("   agents:           \(agentNames)")
        print()
        print("   Run 'xwt start <branch>' to begin your first task.")
    }
}
