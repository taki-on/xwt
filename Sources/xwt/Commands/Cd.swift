import ArgumentParser
import Foundation

struct Cd: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Jump to a branch's worktree directory (requires the xwt shell integration).",
        discussion: """
        `xwt cd` only works when the xwt shell function is loaded in your
        shell. That function intercepts `xwt cd <branch>` and runs `cd` on
        your behalf, because no subprocess can change its parent shell's
        working directory.

        To install the integration, add the appropriate line to your shell's
        rc file:

          zsh   →  ~/.zshrc:                       eval "$(xwt shell-init zsh)"
          bash  →  ~/.bash_profile or ~/.bashrc:   eval "$(xwt shell-init bash)"
          fish  →  ~/.config/fish/config.fish:     xwt shell-init fish | source

        `xwt init` will offer to add the right line for you on first run.
        """
    )

    @Argument(help: "Branch name or slug.")
    var branch: String?

    func run() throws {
        Terminal.errorLine("xwt cd requires the xwt shell integration to be installed")
        Terminal.err()
        Terminal.err("Add the appropriate line to your shell's rc file:")
        Terminal.err(.muted, "  zsh   →  ~/.zshrc:                       eval \"$(xwt shell-init zsh)\"")
        Terminal.err(.muted, "  bash  →  ~/.bash_profile or ~/.bashrc:   eval \"$(xwt shell-init bash)\"")
        Terminal.err(.muted, "  fish  →  ~/.config/fish/config.fish:     xwt shell-init fish | source")
        Terminal.err()
        Terminal.err("Then `source` the file or open a new terminal.")
        Terminal.err(.muted, "Tip: `xwt init` offers to add the right line for you.")
        throw ExitCode.failure
    }
}
