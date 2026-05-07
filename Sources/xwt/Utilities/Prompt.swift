import ArgumentParser
import Foundation

enum Prompt {
    /// Present a numbered list and return the selected value.
    ///
    /// - Parameters:
    ///   - prompt: The question to display.
    ///   - options: The list of options to choose from.
    ///   - defaultIndex: Zero-based index of the default option (selected on empty input).
    ///   - allowNone: When true, adds a "None" option at position 0.
    /// - Returns: The selected option string, or `nil` if "None" was chosen.
    ///
    /// Accepts either a number (`1`..`n`) or a case-insensitive prefix of
    /// exactly one option (e.g. `iph17p` → `iPhone 17 Pro`). On EOF (Ctrl-D)
    /// returns the default if available, otherwise terminates with a clean
    /// error.
    static func choose(
        prompt: String,
        options: [String],
        defaultIndex: Int? = nil,
        allowNone: Bool = false
    ) -> String? {
        guard !options.isEmpty else {
            Terminal.out(prompt)
            Terminal.out(.muted, "  (no options available, skipping)")
            return nil
        }

        Terminal.out(prompt)

        // Build display list: optionally prepend "None"
        var displayOptions: [String] = []
        if allowNone { displayOptions.append("None") }
        displayOptions.append(contentsOf: options)

        // Adjust default index to account for "None" offset
        let adjustedDefault: Int?
        if let di = defaultIndex {
            adjustedDefault = allowNone ? di + 1 : di
        } else if allowNone {
            adjustedDefault = 0
        } else {
            adjustedDefault = nil
        }

        for (i, option) in displayOptions.enumerated() {
            let isDefault = (i == adjustedDefault)
            let marker = isDefault ? Terminal.styled("›", .info) : " "
            let label = isDefault ? Terminal.styled(option, .highlight) : option
            let number = Terminal.styled("[\(i + 1)]", .muted)
            Terminal.out(" \(marker) \(number) \(label)")
        }

        while true {
            if let ad = adjustedDefault {
                Terminal.write("  Choose [\(ad + 1)]: ")
            } else {
                Terminal.write("  Choose: ")
            }

            guard let line = readLine() else {
                // EOF (Ctrl-D / closed stdin). Honour default if any,
                // otherwise exit cleanly so we don't loop forever in pipe mode.
                Terminal.out()
                if let ad = adjustedDefault {
                    let selected = displayOptions[ad]
                    return selected == "None" ? nil : selected
                }
                Terminal.errorLine("no input — exiting")
                Self.exitFailure()
            }

            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                if let ad = adjustedDefault {
                    let selected = displayOptions[ad]
                    return selected == "None" ? nil : selected
                }
                continue
            }

            // Numeric choice
            if let choice = Int(trimmed) {
                guard choice >= 1, choice <= displayOptions.count else {
                    Terminal.out(.muted, "  Invalid choice. Enter a number between 1 and \(displayOptions.count).")
                    continue
                }
                let selected = displayOptions[choice - 1]
                return selected == "None" ? nil : selected
            }

            // Case-insensitive prefix match. Resolves "iph17p" → "iPhone 17 Pro".
            let lower = trimmed.lowercased()
            let matches = displayOptions.filter { $0.lowercased().hasPrefix(lower) }
            if matches.count == 1 {
                let selected = matches[0]
                return selected == "None" ? nil : selected
            } else if matches.count > 1 {
                Terminal.out(.muted, "  Ambiguous — \(matches.count) matches:")
                for m in matches { Terminal.out(.muted, "    \(m)") }
                continue
            }

            Terminal.out(.muted, "  Invalid choice. Enter a number 1–\(displayOptions.count) or a prefix of an option.")
        }
    }

    /// Prompt for free-text input with an optional default.
    ///
    /// - Parameters:
    ///   - prompt: The question to display.
    ///   - defaultValue: Value returned on empty input.
    /// - Returns: The entered string, or `nil` if empty and no default.
    static func input(prompt: String, defaultValue: String? = nil) -> String? {
        if let defaultValue {
            Terminal.write("\(prompt) [\(defaultValue)]: ")
        } else {
            Terminal.write("\(prompt): ")
        }

        guard let line = readLine()?.trimmingCharacters(in: .whitespaces) else {
            return defaultValue
        }

        if line.isEmpty { return defaultValue }
        return line
    }

    /// Throw `ExitCode.failure` from a `Never`-returning context. Used when
    /// `choose` runs out of input and has no default to fall back on.
    private static func exitFailure() -> Never {
        // We're not inside a `throws` context here, so go through the
        // ExitCode raw value directly.
        exit(ExitCode.failure.rawValue)
    }
}
