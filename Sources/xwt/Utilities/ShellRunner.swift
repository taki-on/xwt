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
    static func run(_ arguments: String...) throws -> String {
        try run(arguments)
    }

    @discardableResult
    static func run(_ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        // Read pipes concurrently to avoid deadlock when output exceeds pipe buffer
        var outData = Data()
        var errData = Data()
        let group = DispatchGroup()

        group.enter()
        DispatchQueue.global().async {
            outData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }

        group.enter()
        DispatchQueue.global().async {
            errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }

        group.wait()
        process.waitUntilExit()

        let outString = String(data: outData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let errString = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if process.terminationStatus != 0 {
            throw ShellError.failed(
                command: arguments.joined(separator: " "),
                exitCode: process.terminationStatus,
                stderr: errString
            )
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
