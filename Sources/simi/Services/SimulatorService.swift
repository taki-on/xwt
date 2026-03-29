import Foundation

struct SimulatorInfo {
    let udid: String
    let name: String
    let state: String
    let runtime: String
    let deviceTypeIdentifier: String?

    var isBooted: Bool { state == "Booted" }
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

    /// Create or reuse a simulator. Warns if a reused simulator has a different runtime.
    static func createOrReuse(name: String, deviceType: String, runtime: String) throws -> (udid: String, reused: Bool) {
        if let existing = try find(name: name) {
            let expectedRuntime = runtimeIdentifier(runtime)
            if existing.runtime != expectedRuntime {
                print("   ⚠ Reused simulator has runtime \(existing.runtime),")
                print("     but requested \(expectedRuntime).")
                print("     To recreate: 'simi remove <branch> --delete-simulator' first.")
            }
            return (existing.udid, true)
        }
        let udid = try create(name: name, deviceType: deviceType, runtime: runtime)
        return (udid, false)
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

    /// Convert user-friendly runtime like "iOS 18.2" to simctl identifier.
    static func runtimeIdentifier(_ runtime: String) -> String {
        let sanitized = runtime
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: ".", with: "-")
        return "com.apple.CoreSimulator.SimRuntime.\(sanitized)"
    }
}
