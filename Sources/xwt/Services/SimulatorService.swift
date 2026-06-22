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
    case notFoundForRuntime(name: String, runtime: String)
    case keychainNotFound(String)
    case containerNotFound(udid: String, bundleID: String)
    case sessionNotFound(udid: String, bundleID: String)

    var description: String {
        switch self {
        case .notFound(let id):
            return "Simulator not found: '\(id)'"
        case .notFoundForRuntime(let name, let runtime):
            return "Simulator not found: '\(name)' with runtime '\(runtime)'"
        case .keychainNotFound(let udid):
            return "No keychain database found for simulator \(udid)"
        case .containerNotFound(let udid, let bundleID):
            return "No data container for '\(bundleID)' on simulator \(udid) — is the app installed?"
        case .sessionNotFound(let udid, let bundleID):
            return "No copyable session (cookies / defaults / HTTPStorages) for '\(bundleID)' on simulator \(udid)"
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

    /// Resolve the best *auth source* for a bundle. A simulator name can match
    /// several devices (e.g. multiple "iPhone 17 Pro"); when it does, prefer one
    /// that actually has the app's session so auth is never copied from a
    /// logged-out device. Resolution is otherwise deterministic (booted first,
    /// then lowest UDID) so it never depends on dictionary iteration order.
    ///
    /// When `runtime` is non-nil (a friendly form like "iOS 26.4"), name matches
    /// are first narrowed to that runtime; if none match, this throws
    /// `notFoundForRuntime` rather than falling back to another runtime.
    static func resolveAuthSource(_ nameOrUDID: String, runtime: String?, bundleID: String?) throws -> SimulatorInfo {
        let devices = try fetchAllDevices()
        if let info = devices[nameOrUDID] { return info }  // exact UDID match

        var named = devices.values.filter { $0.name == nameOrUDID }
        if let runtime {
            let runtimeID = runtimeIdentifier(runtime)
            named = named.filter { $0.runtime == runtimeID }
            guard !named.isEmpty else {
                throw SimulatorServiceError.notFoundForRuntime(name: nameOrUDID, runtime: runtime)
            }
        }
        let matches = named.sorted(by: Self.preferredSourceOrder)
        guard let first = matches.first else { throw SimulatorServiceError.notFound(nameOrUDID) }
        guard matches.count > 1, let bundleID else { return first }

        // Disambiguate same-named devices: prefer a logged-in session, then any
        // install, else the deterministic default.
        if let withSession = matches.first(where: { hasSession(udid: $0.udid, bundleID: bundleID) }) {
            return withSession
        }
        if let withContainer = matches.first(where: { appDataContainer(udid: $0.udid, bundleID: bundleID) != nil }) {
            return withContainer
        }
        return first
    }

    /// Stable ordering for ambiguous name matches: booted devices first, then by UDID.
    private static func preferredSourceOrder(_ a: SimulatorInfo, _ b: SimulatorInfo) -> Bool {
        if a.isBooted != b.isBooted { return a.isBooted }
        return a.udid < b.udid
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

    /// `Library` subdirectories that hold an app's login/session state: web and
    /// URL-session cookies (`Cookies`, `HTTPStorages`, `WebKit`) plus the
    /// `UserDefaults` suites apps persist sign-in state in (`Preferences`).
    /// Note these suites aren't always `<bundleID>`-prefixed (e.g. GitHub uses
    /// `com.github.com.session.defaults.<login>@github.com`), so the whole
    /// `Preferences` directory is copied rather than a single plist.
    private static let sessionLibrarySubdirectories = ["Cookies", "Preferences", "HTTPStorages", "WebKit"]

    /// Whether the target app already has a persisted login/session, so callers
    /// can avoid clobbering it on a routine `xwt run`. Looks for copied cookies
    /// or URL-session storage rather than only `httpstorages.sqlite`.
    static func hasSession(udid: String, bundleID: String) -> Bool {
        guard let container = appDataContainer(udid: udid, bundleID: bundleID) else {
            return false
        }
        let fm = FileManager.default

        // Any cookie jar (e.g. `<bundleID>.binarycookies`) implies a session.
        let cookiesDir = container.appendingPathComponent("Library").appendingPathComponent("Cookies")
        if let cookies = try? fm.contentsOfDirectory(atPath: cookiesDir.path),
           cookies.contains(where: { $0.hasSuffix(".binarycookies") }) {
            return true
        }

        // Fall back to non-empty URL-session storage.
        let sqlite = container
            .appendingPathComponent(Paths.httpStoragesSubpath(bundleID: bundleID))
            .appendingPathComponent("httpstorages.sqlite")
        guard let attrs = try? fm.attributesOfItem(atPath: sqlite.path),
              let size = attrs[.size] as? Int else { return false }
        return size > 0
    }

    /// Copy an app's persisted session — cookies, URL-session storage, web data
    /// and `UserDefaults` suites — from one simulator to another so the target
    /// app starts already logged in. Both simulators should be shut down to
    /// avoid SQLite WAL conflicts and to keep `cfprefsd`/`cookied` from
    /// rewriting the freshly-copied files. The app must be installed on both.
    static func copyAppSession(from sourceUDID: String, to targetUDID: String, bundleID: String) throws {
        let fm = FileManager.default
        guard let sourceContainer = appDataContainer(udid: sourceUDID, bundleID: bundleID) else {
            throw SimulatorServiceError.containerNotFound(udid: sourceUDID, bundleID: bundleID)
        }
        guard let targetContainer = appDataContainer(udid: targetUDID, bundleID: bundleID) else {
            throw SimulatorServiceError.containerNotFound(udid: targetUDID, bundleID: bundleID)
        }

        var copiedAny = false
        for subdirectory in sessionLibrarySubdirectories {
            let src = sourceContainer.appendingPathComponent("Library").appendingPathComponent(subdirectory)
            let dst = targetContainer.appendingPathComponent("Library").appendingPathComponent(subdirectory)
            guard fm.fileExists(atPath: src.path) else { continue }
            // Replace the target's copy so a stale journal can't corrupt the
            // freshly copied databases.
            if fm.fileExists(atPath: dst.path) {
                try fm.removeItem(at: dst)
            }
            try fm.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: src, to: dst)
            copiedAny = true
        }

        guard copiedAny else {
            throw SimulatorServiceError.sessionNotFound(udid: sourceUDID, bundleID: bundleID)
        }
    }

    /// Convert user-friendly runtime like "iOS 18.2" to simctl identifier.
    static func runtimeIdentifier(_ runtime: String) -> String {
        let sanitized = runtime
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: ".", with: "-")
        return "com.apple.CoreSimulator.SimRuntime.\(sanitized)"
    }

    /// Map runtime identifiers to their friendly names (e.g.
    /// `com.apple.CoreSimulator.SimRuntime.iOS-26-4` → "iOS 26.4") from the
    /// installed runtimes list. Returns an empty map on failure.
    static func runtimeNamesByIdentifier() -> [String: String] {
        guard let output = try? ShellRunner.run("xcrun", "simctl", "list", "runtimes", "--json"),
              let data = output.data(using: .utf8),
              let list = try? JSONDecoder().decode(RuntimeList.self, from: data) else {
            return [:]
        }
        var map: [String: String] = [:]
        for runtime in list.runtimes { map[runtime.identifier] = runtime.name }
        return map
    }

    private struct RuntimeList: Decodable {
        let runtimes: [Runtime]
        struct Runtime: Decodable {
            let name: String
            let identifier: String
        }
    }
}
