import Foundation

struct SimulatorInfo {
    let udid: String
    let name: String
    let state: String
    let runtime: String
    let deviceTypeIdentifier: String?

    var isBooted: Bool { state == "Booted" }
}

enum SimulatorServiceError: Error, CustomStringConvertible {
    case notFound(String)
    case keychainNotFound(String)

    var description: String {
        switch self {
        case .notFound(let id):
            return "Simulator not found: '\(id)'"
        case .keychainNotFound(let udid):
            return "No keychain database found for simulator \(udid)"
        }
    }
}

enum SimulatorService {
    // MARK: - Decodable helpers

    private struct DeviceList: Decodable {
        let devices: [String: [Device]]
    }

    private struct Device: Decodable {
        let udid: String
        let name: String
        let state: String
        let deviceTypeIdentifier: String?
    }

    // MARK: - Device listing

    /// Fetch all simulator devices, indexed by UDID.
    static func fetchAllDevices() throws -> [String: SimulatorInfo] {
        let output = try ShellRunner.run("xcrun", "simctl", "list", "devices", "--json")
        guard let data = output.data(using: .utf8) else { return [:] }
        let list = try JSONDecoder().decode(DeviceList.self, from: data)
        var result: [String: SimulatorInfo] = [:]
        for (runtimeKey, devices) in list.devices {
            for device in devices {
                result[device.udid] = SimulatorInfo(
                    udid: device.udid,
                    name: device.name,
                    state: device.state,
                    runtime: runtimeKey,
                    deviceTypeIdentifier: device.deviceTypeIdentifier
                )
            }
        }
        return result
    }

    // MARK: - Lookup

    /// Find an existing simulator by name.
    static func find(name: String) throws -> SimulatorInfo? {
        let devices = try fetchAllDevices()
        return devices.values.first(where: { $0.name == name })
    }

    /// Find simulator by UDID from a pre-fetched device map.
    static func findByUDID(_ udid: String, in devices: [String: SimulatorInfo]) -> SimulatorInfo? {
        devices[udid]
    }

    /// Find simulator by UDID (fetches fresh data).
    static func findByUDID(_ udid: String) throws -> SimulatorInfo? {
        try fetchAllDevices()[udid]
    }

    // MARK: - Lifecycle

    /// Create a new simulator. Returns the UDID.
    static func create(name: String, deviceType: String, runtime: String) throws -> String {
        let runtimeID = runtimeIdentifier(runtime)
        let udid = try ShellRunner.run("xcrun", "simctl", "create", name, deviceType, runtimeID)
        return udid
    }

    /// Create or reuse a simulator. The returned `runtimeMismatch` string is
    /// non-nil when an existing simulator is reused but its installed runtime
    /// does not match the requested one — callers should surface that as a
    /// warning at a point in their output flow that doesn't conflict with a
    /// spinner.
    static func createOrReuse(
        name: String,
        deviceType: String,
        runtime: String
    ) throws -> (udid: String, reused: Bool, runtimeMismatch: String?) {
        if let existing = try find(name: name) {
            let expectedRuntime = runtimeIdentifier(runtime)
            if existing.runtime != expectedRuntime {
                let mismatch = "reused simulator has runtime \(existing.runtime), but requested \(expectedRuntime). To recreate: 'xwt remove <branch>' then 'xwt start <branch>'"
                return (existing.udid, true, mismatch)
            }
            return (existing.udid, true, nil)
        }
        let udid = try create(name: name, deviceType: deviceType, runtime: runtime)
        return (udid, false, nil)
    }

    /// Boot a simulator by UDID.
    static func boot(udid: String) throws {
        if let info = try findByUDID(udid), info.isBooted { return }
        try ShellRunner.run("xcrun", "simctl", "boot", udid)
    }

    /// Shutdown a simulator by UDID.
    static func shutdown(udid: String) throws {
        do {
            try ShellRunner.run("xcrun", "simctl", "shutdown", udid)
        } catch {
            // Already shut down — ignore
        }
    }

    /// Delete a simulator by UDID.
    static func delete(udid: String) throws {
        try ShellRunner.run("xcrun", "simctl", "delete", udid)
    }

    // MARK: - App management

    /// Install an app on a simulator.
    static func install(udid: String, appPath: String) throws {
        try ShellRunner.run("xcrun", "simctl", "install", udid, appPath)
    }

    /// Launch an app on a simulator.
    static func launch(udid: String, bundleID: String) throws {
        try ShellRunner.run("xcrun", "simctl", "launch", udid, bundleID)
    }

    // MARK: - Helpers

    /// Resolve a simulator name or UDID to a `SimulatorInfo`.
    static func resolve(_ nameOrUDID: String) throws -> SimulatorInfo {
        let devices = try fetchAllDevices()
        // Try UDID first
        if let info = devices[nameOrUDID] { return info }
        // Fall back to name
        if let info = devices.values.first(where: { $0.name == nameOrUDID }) { return info }
        throw SimulatorServiceError.notFound(nameOrUDID)
    }

    /// Copy keychain database from one simulator to another.
    /// Both simulators should be shut down to avoid SQLite WAL conflicts.
    static func copyKeychain(from sourceUDID: String, to targetUDID: String) throws {
        let sourceDir = Paths.simulatorKeychainDir(udid: sourceUDID)
        let targetDir = Paths.simulatorKeychainDir(udid: targetUDID)
        let fm = FileManager.default

        let mainDB = "keychain-2-debug.db"
        let sourceDB = sourceDir.appendingPathComponent(mainDB)

        guard fm.fileExists(atPath: sourceDB.path) else {
            throw SimulatorServiceError.keychainNotFound(sourceUDID)
        }

        // Ensure target directory exists
        try fm.createDirectory(at: targetDir, withIntermediateDirectories: true)

        // Copy main DB and WAL/SHM journals if present
        for file in [mainDB, "\(mainDB)-shm", "\(mainDB)-wal"] {
            let src = sourceDir.appendingPathComponent(file)
            let dst = targetDir.appendingPathComponent(file)
            guard fm.fileExists(atPath: src.path) else { continue }
            if fm.fileExists(atPath: dst.path) {
                try fm.removeItem(at: dst)
            }
            try fm.copyItem(at: src, to: dst)
        }
    }

    /// Convert user-friendly runtime like "iOS 18.2" to simctl identifier.
    static func runtimeIdentifier(_ runtime: String) -> String {
        let sanitized = runtime
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: ".", with: "-")
        return "com.apple.CoreSimulator.SimRuntime.\(sanitized)"
    }
}
