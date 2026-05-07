import Darwin
import Dispatch
import Foundation

/// A single-line terminal spinner for long-running, output-quiet operations.
///
/// Use this only around `ShellRunner.run(...)` calls (which capture stdout/
/// stderr) — never around `ShellRunner.exec(...)`, where subprocess output
/// would interleave with the spinner redraw and produce garbage.
///
/// On a non-TTY (`Terminal.colorEnabled == false`), the spinner degrades to
/// a single `"<message>…"` line on `start()` and emits nothing on `stop()` —
/// no escape sequences, no garbage in piped output.
final class Spinner {
    /// The currently-active spinner, if any. Read by the SIGINT handler so
    /// it can restore the cursor and erase the in-flight redraw before the
    /// process exits. There is at most one active spinner at any time.
    static var active: Spinner?

    private static let frames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
    private static let frameInterval: DispatchTimeInterval = .milliseconds(80)

    private let message: String
    private let isAnimated: Bool
    private var timer: DispatchSourceTimer?
    private var frameIndex = 0

    /// Create and start a spinner. The animation only runs when stdout is a
    /// real TTY with color enabled.
    @discardableResult
    init(_ message: String) {
        self.message = message
        self.isAnimated = Terminal.colorEnabled
        Spinner.active = self
        if isAnimated {
            // Hide the cursor and draw the first frame immediately.
            print("\u{1B}[?25l", terminator: "")
            tick()
            startTimer()
        } else {
            // Pipe / dumb terminal: announce once, then stay quiet.
            print("\(message)…")
        }
    }

    private func startTimer() {
        let t = DispatchSource.makeTimerSource(queue: .global(qos: .userInitiated))
        t.schedule(deadline: .now() + Spinner.frameInterval, repeating: Spinner.frameInterval)
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        self.timer = t
    }

    private func tick() {
        let frame = Spinner.frames[frameIndex % Spinner.frames.count]
        frameIndex += 1
        // \r → column 0, \e[2K → erase entire line, then redraw.
        let styled = Terminal.styled(frame, .info)
        print("\r\u{1B}[2K\(styled) \(message)", terminator: "")
        fflush(stdout)
    }

    /// Stop the spinner and write a final one-line state with `✓` / `✗`.
    /// `final` defaults to the original message; pass a different string to
    /// reflect the actual outcome (e.g. include the resulting UDID).
    func stop(_ status: Status = .success, message final: String? = nil) {
        timer?.cancel()
        timer = nil
        if Spinner.active === self { Spinner.active = nil }
        guard isAnimated else { return }
        let icon: String
        switch status {
        case .success: icon = Terminal.styled("✓", .success)
        case .failure: icon = Terminal.styled("✗", .failure)
        case .silent:  icon = ""
        }
        let text = final ?? message
        print("\r\u{1B}[2K\(icon)\(icon.isEmpty ? "" : " ")\(text)")
        // Restore cursor.
        print("\u{1B}[?25h", terminator: "")
        fflush(stdout)
    }

    /// Erase the in-flight spinner line and restore the cursor without
    /// emitting any final state. Used by the SIGINT handler.
    func cancel() {
        timer?.cancel()
        timer = nil
        if Spinner.active === self { Spinner.active = nil }
        guard isAnimated else { return }
        print("\r\u{1B}[2K", terminator: "")
        print("\u{1B}[?25h", terminator: "")
        fflush(stdout)
    }

    enum Status {
        case success
        case failure
        case silent
    }

    /// Run `work` with a spinner showing `message`. Stops with `.success` (and
    /// optional `final` text) on normal completion, `.failure` on throw.
    /// Single-line in a TTY (animated then final state); a single
    /// `"<message>…"` line in piped/dumb output.
    @discardableResult
    static func around<T>(
        _ message: String,
        final: String? = nil,
        _ work: () throws -> T
    ) rethrows -> T {
        let spinner = Spinner(message)
        do {
            let result = try work()
            spinner.stop(.success, message: final)
            return result
        } catch {
            spinner.stop(.failure)
            throw error
        }
    }
}

/// Install a SIGINT handler that restores the cursor and erases an in-flight
/// spinner line before exiting. Without this, Ctrl-C during a spinner leaves
/// the cursor hidden and the terminal showing a half-drawn frame.
///
/// The handler is async-signal-safe: it writes a fixed-length escape sequence
/// directly to fd 1 and calls `_exit`, avoiding `print`, `malloc`, and other
/// non-reentrant Foundation/Swift runtime calls. Idempotent — safe to call
/// once at program start.
enum SignalHandler {
    private static var installed = false

    static func install() {
        guard !installed else { return }
        installed = true
        // \r → col 0, \e[2K → erase line, \e[?25h → show cursor, \n → newline.
        signal(SIGINT) { _ in
            let restore = "\r\u{1B}[2K\u{1B}[?25h\n"
            _ = restore.withCString { write(STDOUT_FILENO, $0, strlen($0)) }
            // SIGINT convention: 128 + signal number.
            _exit(130)
        }
    }
}
