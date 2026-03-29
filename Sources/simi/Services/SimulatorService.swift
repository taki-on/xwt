import Foundation

struct SimulatorInfo {
    let udid: String
    let name: String
    let state: String

    var isBooted: Bool { state == "Booted" }
}

enum SimulatorService {
    /// Find an existing simulator by name.
    static func find(name: String) throws -> SimulatorInfo? {
        let output = try ShellRunner.run("xcrun", "simctl", "list", "devices", "--json")
        guard let data = output.data(using: .utf8) else { return nil }

        struct DeviceList: Decodable {
            let devices: [String: [Device]]
        }
        struct Device: Decodable {
            let udid: String
            let name: String
            let state: String
        }

        let list = try JSONDecoder().decode(DeviceList.self, from: data)
        for (_, devices) in list.devices {
            if let device = devices.first(where: { $0.name == name }) {
                return SimulatorInfo(udid: device.udid, name: device.name, state: device.state)
            }
        }
        return nil
    }

    /// Create a new simulator. Returns the UDID.
    static func create(name: String, deviceType: String, runtime: String) throws -> String {
        // simctl expects runtime identifiers like com.apple.CoreSimulator.SimRuntime.iOS-18-2
        let runtimeID = runtimeIdentifier(runtime)
        let udid = try ShellRunner.run("xcrun", "simctl", "create", name, deviceType, runtimeID)
        return udid
    }

    /// Create or reuse a simulator. Returns UDID.
    static func createOrReuse(name: String, deviceType: String, runtime: String) throws -> (udid: String, reused: Bool) {
        if let existing = try find(name: name) {
            return (existing.udid, true)
        }
        let udid = try create(name: name, deviceType: deviceType, runtime: runtime)
        return (udid, false)
    }

    /// Boot a simulator by UDID.
    static func boot(udid: String) throws {
        // Check if already booted
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

    /// Find simulator by UDID.
    static func findByUDID(_ udid: String) throws -> SimulatorInfo? {
        let output = try ShellRunner.run("xcrun", "simctl", "list", "devices", "--json")
        guard let data = output.data(using: .utf8) else { return nil }

        struct DeviceList: Decodable {
            let devices: [String: [Device]]
        }
        struct Device: Decodable {
            let udid: String
            let name: String
            let state: String
        }

        let list = try JSONDecoder().decode(DeviceList.self, from: data)
        for (_, devices) in list.devices {
            if let device = devices.first(where: { $0.udid == udid }) {
                return SimulatorInfo(udid: device.udid, name: device.name, state: device.state)
            }
        }
        return nil
    }

    /// Convert user-friendly runtime like "iOS 18.2" to simctl identifier.
    private static func runtimeIdentifier(_ runtime: String) -> String {
        // "iOS 18.2" → "com.apple.CoreSimulator.SimRuntime.iOS-18-2"
        let sanitized = runtime
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: ".", with: "-")
        return "com.apple.CoreSimulator.SimRuntime.\(sanitized)"
    }
}
