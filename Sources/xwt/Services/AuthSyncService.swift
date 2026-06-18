import Foundation

/// Outcome of an auth-sync attempt.
enum AuthSyncResult {
    /// Auth state was copied.
    case copied
    /// Nothing to do (shared simulator, or nothing requested).
    case skipped
    /// The copy failed (a warning was already logged).
    case failed
}

/// Copies auth state — the simulator keychain and/or an app's session cookies
/// (URL-session `HTTPStorages`) — from a source simulator to a target so a new
/// worktree's simulator starts already logged in.
enum AuthSyncService {
    /// Copy auth state from `sourceID` to `targetUDID`. Non-fatal: logs a
    /// warning and returns `.failed` on error rather than throwing, so callers
    /// can continue setting up a task.
    ///
    /// - Parameters:
    ///   - bundleID: when non-nil, also copy the app's `HTTPStorages` session.
    ///     Requires the app to be installed on both simulators.
    ///   - includeKeychain: copy the simulator-level keychain.
    ///   - terminateTargetApp: terminate the app on the target before copying
    ///     its session (used by an explicit `xwt sync-auth` force re-sync).
    @discardableResult
    static func sync(
        fromSource sourceID: String,
        toTargetUDID targetUDID: String,
        bundleID: String?,
        includeKeychain: Bool,
        terminateTargetApp: Bool
    ) -> AuthSyncResult {
        let source: SimulatorInfo
        do {
            source = try SimulatorService.resolve(sourceID)
        } catch {
            warnFailure(error)
            return .failed
        }

        // Shared simulator (e.g. stacked tasks) — auth is already shared.
        guard source.udid != targetUDID else {
            Terminal.out(.muted, "    ↳ source and target share a simulator — skipping auth copy")
            return .skipped
        }

        let what: String
        switch (includeKeychain, bundleID != nil) {
        case (true, true):   what = "keychain + session"
        case (true, false):  what = "keychain"
        case (false, true):  what = "session"
        case (false, false):
            return .skipped  // nothing requested
        }
        Terminal.out(.info, "  › Copying \(what) from '\(source.name)' \(Terminal.styled("(\(source.udid))", .muted))")

        // Flush the source so SQLite WAL journals are checkpointed before copy.
        let wasBooted = source.isBooted
        if wasBooted {
            Terminal.out(.muted, "    ↳ shutting down source simulator to flush data")
            try? SimulatorService.shutdown(udid: source.udid)
            Thread.sleep(forTimeInterval: 1)
        }
        defer {
            if wasBooted {
                Terminal.out(.muted, "    ↳ rebooting source simulator")
                try? SimulatorService.boot(udid: source.udid)
            }
        }

        do {
            if terminateTargetApp, let bundleID {
                SimulatorService.terminate(udid: targetUDID, bundleID: bundleID)
            }
            if includeKeychain {
                try SimulatorService.copyKeychain(from: source.udid, to: targetUDID)
                Terminal.out(.muted, "    ↳ keychain copied")
            }
            if let bundleID {
                try SimulatorService.copyHTTPStorages(from: source.udid, to: targetUDID, bundleID: bundleID)
                Terminal.out(.muted, "    ↳ session (cookies) copied")
            }
            return .copied
        } catch {
            warnFailure(error)
            return .failed
        }
    }

    private static func warnFailure(_ error: Error) {
        Terminal.warningLine("could not copy auth: \(error)")
        Terminal.err(.muted, "    ↳ you may need to log in manually on the new simulator")
    }
}
