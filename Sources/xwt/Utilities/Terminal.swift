import Darwin
import Foundation

/// Pure-Swift terminal capability detection, ANSI styling, and output helpers.
///
/// All output in xwt should flow through `Terminal.out(...)` (stdout) and
/// `Terminal.err(...)` (stderr). Capability flags are computed once at first
/// access and respect:
///
///   1. `NO_COLOR` (any non-empty value)        — disables color
///      (https://no-color.org/)
///   2. `CLICOLOR_FORCE` / `FORCE_COLOR`        — force color on (overrides isatty)
///      (https://bixense.com/clicolors/)
///   3. `TERM=dumb`                              — disables color
///   4. `CLICOLOR=0`                             — disables color
///   5. `isatty(fd)`                             — auto-detect
///
/// Color depth is intentionally limited to the 16-color ANSI set so that user
/// terminal themes (Solarized, Dracula, Nord, etc.) keep working as expected.
enum Terminal {
    /// Whether ANSI color/style codes should be emitted on stdout.
    static let colorEnabled: Bool = shouldUseColor(fd: STDOUT_FILENO)

    /// Whether ANSI color/style codes should be emitted on stderr.
    static let stderrColorEnabled: Bool = shouldUseColor(fd: STDERR_FILENO)

    // MARK: - Styling

    /// Wrap `message` in SGR codes for `style`. No-op when stdout color is off.
    static func styled(_ message: String, _ style: Style) -> String {
        guard colorEnabled, let sgr = style.sgr else { return message }
        return "\u{1B}[\(sgr)m\(message)\u{1B}[0m"
    }

    /// Wrap `message` in SGR codes for `style`. No-op when stderr color is off.
    static func styledForStderr(_ message: String, _ style: Style) -> String {
        guard stderrColorEnabled, let sgr = style.sgr else { return message }
        return "\u{1B}[\(sgr)m\(message)\u{1B}[0m"
    }

    // MARK: - Output

    /// Print a plain (unstyled) line to stdout.
    static func out(_ message: String = "") {
        print(message)
    }

    /// Print a styled line to stdout.
    static func out(_ style: Style, _ message: String) {
        print(styled(message, style))
    }

    /// Write to stdout without a trailing newline. Used for inline prompts.
    static func write(_ message: String) {
        print(message, terminator: "")
        fflush(stdout)
    }

    /// Print a plain line to stderr.
    static func err(_ message: String = "") {
        write(message + "\n", to: FileHandle.standardError)
    }

    /// Print a styled line to stderr.
    static func err(_ style: Style, _ message: String) {
        write(styledForStderr(message, style) + "\n", to: FileHandle.standardError)
    }

    /// Write a cargo-style `error: …` line (bold red prefix) to stderr.
    static func errorLine(_ message: String) {
        let prefix = styledForStderr("error:", .failure)
        write("\(prefix) \(message)\n", to: FileHandle.standardError)
    }

    /// Write a cargo-style `warning: …` line (bold yellow prefix) to stderr.
    static func warningLine(_ message: String) {
        let prefix = styledForStderr("warning:", .warning)
        write("\(prefix) \(message)\n", to: FileHandle.standardError)
    }

    /// Write a cargo-style `note: …` line (cyan prefix) to stderr.
    static func noteLine(_ message: String) {
        let prefix = styledForStderr("note:", .info)
        write("\(prefix) \(message)\n", to: FileHandle.standardError)
    }

    // MARK: - Terminal width

    /// Best-effort terminal column count from `ioctl(TIOCGWINSZ)`. Falls back
    /// to 80 when stdout is not a TTY or the call fails.
    static func terminalWidth() -> Int {
        var ws = winsize()
        if ioctl(STDOUT_FILENO, TIOCGWINSZ, &ws) == 0, ws.ws_col > 0 {
            return Int(ws.ws_col)
        }
        return 80
    }

    // MARK: - Internals

    private static func write(_ s: String, to handle: FileHandle) {
        if let data = s.data(using: .utf8) {
            handle.write(data)
        }
    }

    private static func shouldUseColor(fd: Int32) -> Bool {
        let env = ProcessInfo.processInfo.environment
        if let v = env["NO_COLOR"], !v.isEmpty { return false }
        if let v = env["CLICOLOR_FORCE"], !v.isEmpty { return true }
        if let v = env["FORCE_COLOR"], !v.isEmpty { return true }
        if env["TERM"] == "dumb" { return false }
        if env["CLICOLOR"] == "0" { return false }
        return isatty(fd) == 1
    }
}

/// Semantic styles. Always name styles by intent — never by raw color — so
/// the palette can change in one place. Each style maps to a single SGR
/// parameter sequence within the 16-color ANSI set.
enum Style {
    case success    // bold green
    case failure    // bold red
    case warning    // bold yellow
    case info       // cyan
    case muted      // bright black (gray)
    case highlight  // bold
    case heading    // bold

    /// SGR parameters for this style, or `nil` for an unstyled passthrough.
    fileprivate var sgr: String? {
        switch self {
        case .success:   return "1;32"
        case .failure:   return "1;31"
        case .warning:   return "1;33"
        case .info:      return "36"
        case .muted:     return "90"
        case .highlight: return "1"
        case .heading:   return "1"
        }
    }
}

extension String {
    /// Strip ANSI CSI sequences (`ESC [ … <final>`) from the string.
    /// Used for visible-width measurement when a string already contains
    /// embedded SGR codes.
    var strippingANSI: String {
        var result = ""
        result.reserveCapacity(count)
        var i = startIndex
        while i < endIndex {
            let c = self[i]
            if c == "\u{1B}" {
                let next = index(after: i)
                if next < endIndex && self[next] == "[" {
                    var j = index(after: next)
                    while j < endIndex {
                        let cc = self[j]
                        j = index(after: j)
                        if cc.isLetter { break }
                    }
                    i = j
                    continue
                }
            }
            result.append(c)
            i = index(after: i)
        }
        return result
    }

    /// Approximate visible terminal width, ignoring ANSI codes and treating
    /// emoji-presentation scalars as width 2. Good enough for column padding
    /// in xwt's summary blocks; not a full Unicode width implementation.
    var visibleWidth: Int {
        var width = 0
        for scalar in strippingANSI.unicodeScalars {
            if scalar.properties.isEmojiPresentation && scalar.value > 127 {
                width += 2
            } else {
                width += 1
            }
        }
        return width
    }
}
