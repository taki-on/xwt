import Foundation

enum ShellError: Error, CustomStringConvertible {
    case failed(command: String, exitCode: Int32, stderr: String)

    var description: String {
        switch self {
        case .failed(let cmd, let code, let stderr):
            return "Command failed (\(code)): \(cmd)\n\(stderr)"
        }
    }
}

enum ShellRunner {
    @discardableResult
    static func run(_ arguments: String..., quiet: Bool = false) throws -> String {
        try run(arguments, quiet: quiet)
    }

    @discardableResult
    static func run(_ arguments: [String], quiet: Bool = false) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        let outString = String(data: outData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let errString = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if process.terminationStatus != 0 {
            throw ShellError.failed(
                command: arguments.joined(separator: " "),
                exitCode: process.terminationStatus,
                stderr: errString
            )
        }

        if !quiet && !outString.isEmpty {
            // Caller can choose to print or not
        }

        return outString
    }

    /// Run and stream output directly to stdout/stderr (for xcodebuild etc.)
    static func exec(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = arguments
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            throw ShellError.failed(
                command: arguments.joined(separator: " "),
                exitCode: process.terminationStatus,
                stderr: ""
            )
        }
    }
}
