import Foundation

/// Per-shell metadata and file-IO primitives for installing the
/// `xwt shell-init` wrapper into the user's shell rc file.
///
/// This is the shared backend behind two interactive flows:
///   - `xwt init` offers to install the wrapper as part of first-run setup.
///   - `xwt cd` (when the wrapper is not yet loaded) offers to install it
///     on the fly, so users hit the right answer the first time they run
///     into the limitation.
///
/// The service is intentionally UI-free — callers compose their own prompts
/// around `detect()` / `isInstalled(in:)` / `append(to:)`.
enum ShellIntegration {

    /// Resolved metadata for installing the xwt shell wrapper for a
    /// particular shell.
    struct Info {
        let shellName: String      // "zsh" | "bash" | "fish"
        let rcFileURL: URL
        let installLine: String

        var rcFilePath: String { rcFileURL.path }

        /// `~`-prefixed path suitable for user-facing messages.
        var displayPath: String {
            rcFileURL.path.replacingOccurrences(
                of: NSHomeDirectory(),
                with: "~"
            )
        }
    }

    /// Detect the user's shell from `$SHELL` and resolve the rc file +
    /// install line. Returns `nil` for unsupported shells (or when
    /// `$SHELL` is unset or unparseable).
    static func detect() -> Info? {
        let env = ProcessInfo.processInfo.environment
        guard let shellPath = env["SHELL"], !shellPath.isEmpty else { return nil }
        let shellName = (shellPath as NSString).lastPathComponent
        let home = FileManager.default.homeDirectoryForCurrentUser

        switch shellName {
        case "zsh":
            return Info(
                shellName: "zsh",
                rcFileURL: home.appendingPathComponent(".zshrc"),
                installLine: #"eval "$(xwt shell-init zsh)""#
            )
        case "bash":
            // On macOS interactive login shells read ~/.bash_profile,
            // not ~/.bashrc. Prefer .bash_profile if it already exists;
            // otherwise create/use .bashrc.
            let bashProfile = home.appendingPathComponent(".bash_profile")
            let bashrc = home.appendingPathComponent(".bashrc")
            let target = FileManager.default.fileExists(atPath: bashProfile.path)
                ? bashProfile
                : bashrc
            return Info(
                shellName: "bash",
                rcFileURL: target,
                installLine: #"eval "$(xwt shell-init bash)""#
            )
        case "fish":
            return Info(
                shellName: "fish",
                rcFileURL: home
                    .appendingPathComponent(".config/fish/config.fish"),
                installLine: "xwt shell-init fish | source"
            )
        default:
            return nil
        }
    }

    /// Whether the shell integration is already present in the resolved
    /// rc file. Substring match across the file — robust to minor
    /// whitespace tweaks the user may have made. We're looking for
    /// `xwt shell-init` anywhere in the file.
    static func isInstalled(in info: Info) -> Bool {
        guard let content = try? String(contentsOf: info.rcFileURL, encoding: .utf8) else {
            return false
        }
        return content.contains("xwt shell-init")
            || content.contains(info.installLine)
    }

    /// Append a small block (header comment + install line) to the rc
    /// file, creating the file (and any missing parent directories) as
    /// needed.
    static func append(to info: Info) throws {
        try FileManager.default.createDirectory(
            at: info.rcFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var content = ""
        if FileManager.default.fileExists(atPath: info.rcFileURL.path) {
            content = try String(contentsOf: info.rcFileURL, encoding: .utf8)
        }
        if !content.isEmpty && !content.hasSuffix("\n") {
            content += "\n"
        }
        content += "\n# Added by xwt — shell integration (cd / auto-cd-on-start).\n"
        content += info.installLine + "\n"

        try content.write(to: info.rcFileURL, atomically: true, encoding: .utf8)
    }
}
