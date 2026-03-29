import ArgumentParser

@main
struct Simi: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "simi",
        abstract: "Orchestrate git worktrees and iOS Simulators for parallel branch development.",
        version: "0.1.0",
        subcommands: [Start.self, List.self, Shell.self, Run.self, Remove.self]
    )
}
