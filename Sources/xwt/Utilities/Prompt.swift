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
    static func choose(
        prompt: String,
        options: [String],
        defaultIndex: Int? = nil,
        allowNone: Bool = false
    ) -> String? {
        guard !options.isEmpty else {
            print(prompt)
            print("  (no options available, skipping)")
            return nil
        }

        print(prompt)

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
            let marker = (i == adjustedDefault) ? " (default)" : ""
            print("  [\(i + 1)] \(option)\(marker)")
        }

        while true {
            if let ad = adjustedDefault {
                print("  Choose [\(ad + 1)]: ", terminator: "")
            } else {
                print("  Choose: ", terminator: "")
            }

            guard let line = readLine()?.trimmingCharacters(in: .whitespaces) else {
                return adjustedDefault.flatMap { displayOptions[$0] == "None" ? nil : displayOptions[$0] }
            }

            if line.isEmpty {
                if let ad = adjustedDefault {
                    let selected = displayOptions[ad]
                    return selected == "None" ? nil : selected
                }
                continue
            }

            guard let choice = Int(line), choice >= 1, choice <= displayOptions.count else {
                print("  Invalid choice. Enter a number between 1 and \(displayOptions.count).")
                continue
            }

            let selected = displayOptions[choice - 1]
            return selected == "None" ? nil : selected
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
            print("\(prompt) [\(defaultValue)]: ", terminator: "")
        } else {
            print("\(prompt): ", terminator: "")
        }

        guard let line = readLine()?.trimmingCharacters(in: .whitespaces) else {
            return defaultValue
        }

        if line.isEmpty { return defaultValue }
        return line
    }
}
