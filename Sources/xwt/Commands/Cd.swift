import ArgumentParser
import Darwin
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
        When run interactively, `xwt cd` itself also offers to install the
        integration if it isn't there yet.
        """
    )

    @Argument(help: "Branch name or slug.")
    var branch: String?

    func run() throws {
        // Reaching this command implies the shell wrapper is not active in
        // this shell — when it is, the wrapper intercepts `xwt cd …` and
        // never invokes the binary. Three sub-cases to handle:
        //   1. The integration line is already in the rc file → user just
        //      needs to `source` it (or open a new terminal).
        //   2. The line isn't in the rc file and we're on a TTY → offer to
        //      add it inline.
        //   3. Unsupported shell or non-interactive stdin → fall back to
        //      manual instructions.
        Terminal.errorLine("xwt cd requires the xwt shell integration to be installed")
        Terminal.err()

        guard let info = ShellIntegration.detect() else {
            printManualInstructions()
            throw ExitCode.failure
        }

        if ShellIntegration.isInstalled(in: info) {
            Terminal.err("The integration is installed in \(info.displayPath) but isn't loaded in this shell.")
            Terminal.err(.muted, "    ↳ run `source \(info.displayPath)` or open a new terminal, then re-run `xwt cd …`")
            throw ExitCode.failure
        }

        guard isStdinTTY() else {
            printManualInstructions()
            throw ExitCode.failure
        }

        Terminal.err("Detected \(info.shellName). I can add the integration to \(info.displayPath) for you.")
        Terminal.err(.muted, "  Enables `xwt cd <branch>` and auto-cd after `xwt start`.")
        Terminal.err()

        let selected = Prompt.choose(
            prompt: "🐚 Install xwt shell integration for \(info.shellName)?",
            options: ["Add to \(info.displayPath)"],
            allowNone: true
        )

        guard selected != nil else {
            Terminal.err()
            Terminal.err(.muted, "Skipped. Install later with `xwt shell-init \(info.shellName)` or `xwt init`.")
            throw ExitCode.failure
        }

        do {
            try ShellIntegration.append(to: info)
            Terminal.out(.success, "  ✓ Added shell integration to \(info.displayPath)")
            Terminal.out(.muted, "    ↳ run `source \(info.displayPath)` or open a new terminal, then re-run `xwt cd …`")
        } catch {
            Terminal.warningLine("could not update \(info.displayPath): \(error.localizedDescription)")
        }
        // Still exit non-zero — we couldn't actually cd this invocation,
        // and the next one (in a reloaded shell) will succeed via the wrapper.
        throw ExitCode.failure
    }

    private func printManualInstructions() {
        Terminal.err("Add the appropriate line to your shell's rc file:")
        Terminal.err(.muted, "  zsh   →  ~/.zshrc:                       eval \"$(xwt shell-init zsh)\"")
        Terminal.err(.muted, "  bash  →  ~/.bash_profile or ~/.bashrc:   eval \"$(xwt shell-init bash)\"")
        Terminal.err(.muted, "  fish  →  ~/.config/fish/config.fish:     xwt shell-init fish | source")
        Terminal.err()
        Terminal.err("Then `source` the file or open a new terminal.")
        Terminal.err(.muted, "Tip: `xwt init` offers to add the right line for you.")
    }

    private func isStdinTTY() -> Bool {
        return isatty(STDIN_FILENO) == 1
    }
}
