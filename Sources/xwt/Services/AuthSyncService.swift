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
    ///   - bundleID: when non-nil, also copy the app's persisted session
    ///     (cookies, URL-session storage, web data and `UserDefaults` suites).
    ///     Requires the app to be installed on both simulators.
    ///   - includeKeychain: copy the simulator-level keychain.
    ///   - quiesceTarget: shut the target simulator down for the copy (used by
    ///     the explicit `xwt sync-auth` force re-sync, where the app may be
    ///     running) so `cfprefsd`/`cookied` can't overwrite the copied files.
    @discardableResult
    static func sync(
        fromSource sourceID: String,
        toTargetUDID targetUDID: String,
        bundleID: String?,
        includeKeychain: Bool,
        quiesceTarget: Bool
    ) -> AuthSyncResult {
        let source: SimulatorInfo
        do {
            source = try SimulatorService.resolveAuthSource(sourceID, bundleID: bundleID)
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

        // Quiesce the simulators so SQLite WAL journals are checkpointed and no
        // running daemon (`cfprefsd`/`cookied`) rewrites the files mid-copy.
        // Always for the source; for the target only on an explicit force
        // re-sync, where the app (and its preferences) may be live.
        let sourceWasBooted = source.isBooted
        if sourceWasBooted {
            Terminal.out(.muted, "    ↳ shutting down source simulator to flush data")
            try? SimulatorService.shutdown(udid: source.udid)
        }
        let targetWasBooted = quiesceTarget
            && (((try? SimulatorService.findByUDID(targetUDID)) ?? nil)?.isBooted ?? false)
        if targetWasBooted {
            Terminal.out(.muted, "    ↳ shutting down target simulator to apply session")
            try? SimulatorService.shutdown(udid: targetUDID)
        }
        if sourceWasBooted || targetWasBooted {
            Thread.sleep(forTimeInterval: 1)
        }
        defer {
            if sourceWasBooted {
                Terminal.out(.muted, "    ↳ rebooting source simulator")
                try? SimulatorService.boot(udid: source.udid)
            }
            if targetWasBooted {
                Terminal.out(.muted, "    ↳ rebooting target simulator")
                try? SimulatorService.boot(udid: targetUDID)
            }
        }

        do {
            if includeKeychain {
                try SimulatorService.copyKeychain(from: source.udid, to: targetUDID)
                Terminal.out(.muted, "    ↳ keychain copied")
            }
            if let bundleID {
                try SimulatorService.copyAppSession(from: source.udid, to: targetUDID, bundleID: bundleID)
                Terminal.out(.muted, "    ↳ session (cookies + defaults) copied")
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
