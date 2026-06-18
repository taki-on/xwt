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
    case containerNotFound(udid: String, bundleID: String)
    case sessionNotFound(udid: String, bundleID: String)

    var description: String {
        switch self {
        case .notFound(let id):
            return "Simulator not found: '\(id)'"
        case .keychainNotFound(let udid):
            return "No keychain database found for simulator \(udid)"
        case .containerNotFound(let udid, let bundleID):
            return "No data container for '\(bundleID)' on simulator \(udid) — is the app installed?"
        case .sessionNotFound(let udid, let bundleID):
            return "No session storage (HTTPStorages) for '\(bundleID)' on simulator \(udid)"
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

    /// Terminate a running app on a simulator. Ignores "not running" errors.
    static func terminate(udid: String, bundleID: String) {
        _ = try? ShellRunner.run("xcrun", "simctl", "terminate", udid, bundleID)
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

        // Copy main DB and WAL/SHM journals. Always clear the target's existing
        // files first so a stale journal can't corrupt the freshly copied DB.
        for file in [mainDB, "\(mainDB)-shm", "\(mainDB)-wal"] {
            let src = sourceDir.appendingPathComponent(file)
            let dst = targetDir.appendingPathComponent(file)
            if fm.fileExists(atPath: dst.path) {
                try fm.removeItem(at: dst)
            }
            if fm.fileExists(atPath: src.path) {
                try fm.copyItem(at: src, to: dst)
            }
        }
    }

    // MARK: - App session (cookies / URL session storage)

    /// Resolve an app's data container directory on a simulator by scanning each
    /// container's `.com.apple.mobile_container_manager.metadata.plist` for a
    /// matching `MCMMetadataIdentifier`. Works while the simulator is shut down
    /// (unlike `simctl get_app_container`, which requires a booted device).
    static func appDataContainer(udid: String, bundleID: String) -> URL? {
        let appsDir = Paths.simulatorContainersDataAppDir(udid: udid)
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: appsDir, includingPropertiesForKeys: nil
        ) else { return nil }

        for container in entries {
            let metadata = container.appendingPathComponent(
                ".com.apple.mobile_container_manager.metadata.plist"
            )
            guard let data = try? Data(contentsOf: metadata),
                  let plist = try? PropertyListSerialization.propertyList(
                    from: data, options: [], format: nil
                  ) as? [String: Any],
                  let identifier = plist["MCMMetadataIdentifier"] as? String
            else { continue }
            if identifier == bundleID { return container }
        }
        return nil
    }

    /// Whether the target app already has persisted URL-session storage. Used to
    /// avoid clobbering an established session on a subsequent `xwt run`.
    static func hasSession(udid: String, bundleID: String) -> Bool {
        guard let container = appDataContainer(udid: udid, bundleID: bundleID) else {
            return false
        }
        let sqlite = container
            .appendingPathComponent(Paths.httpStoragesSubpath(bundleID: bundleID))
            .appendingPathComponent("httpstorages.sqlite")
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: sqlite.path),
              let size = attrs[.size] as? Int else { return false }
        return size > 0
    }

    /// Copy an app's `HTTPStorages/<bundleID>` (cookies / URL-session storage)
    /// from one simulator to another. Both simulators should be shut down to
    /// avoid SQLite WAL conflicts. The target app must already be installed.
    static func copyHTTPStorages(from sourceUDID: String, to targetUDID: String, bundleID: String) throws {
        let fm = FileManager.default
        guard let sourceContainer = appDataContainer(udid: sourceUDID, bundleID: bundleID) else {
            throw SimulatorServiceError.containerNotFound(udid: sourceUDID, bundleID: bundleID)
        }
        guard let targetContainer = appDataContainer(udid: targetUDID, bundleID: bundleID) else {
            throw SimulatorServiceError.containerNotFound(udid: targetUDID, bundleID: bundleID)
        }

        let subpath = Paths.httpStoragesSubpath(bundleID: bundleID)
        let sourceDir = sourceContainer.appendingPathComponent(subpath)
        let targetDir = targetContainer.appendingPathComponent(subpath)

        let mainDB = "httpstorages.sqlite"
        guard fm.fileExists(atPath: sourceDir.appendingPathComponent(mainDB).path) else {
            throw SimulatorServiceError.sessionNotFound(udid: sourceUDID, bundleID: bundleID)
        }

        try fm.createDirectory(at: targetDir, withIntermediateDirectories: true)

        // Always clear the target's existing files first so a stale journal
        // can't corrupt the freshly copied database.
        for file in [mainDB, "\(mainDB)-shm", "\(mainDB)-wal"] {
            let src = sourceDir.appendingPathComponent(file)
            let dst = targetDir.appendingPathComponent(file)
            if fm.fileExists(atPath: dst.path) {
                try fm.removeItem(at: dst)
            }
            if fm.fileExists(atPath: src.path) {
                try fm.copyItem(at: src, to: dst)
            }
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
