import ArgumentParser

@main
struct Xwt: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "xwt",
        abstract: "Orchestrate git worktrees and iOS Simulators for parallel branch development.",
        version: xwtVersion,
        subcommands: [Init.self, Start.self, List.self, Run.self, Remove.self, PR.self, Restack.self]
    )
}
