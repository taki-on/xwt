import Foundation

enum BuiltAppError: Error, CustomStringConvertible {
    case notFound(productsDir: String)

    var description: String {
        switch self {
        case .notFound(let dir):
            return "no .app bundle found in \(dir)"
        }
    }
}

/// Locating a built `.app` bundle in DerivedData and reading its bundle ID.
/// Shared by `xwt run` and `xwt sync-auth`.
enum BuiltApp {
    /// Find the `.app` bundle built for the simulator in DerivedData.
    /// Throws `BuiltAppError.notFound` when no bundle is present.
    static func findApp(derivedDataPath: String) throws -> String {
        let productsDir = "\(derivedDataPath)/Build/Products"
        let output = try ShellRunner.run("find", productsDir, "-name", "*.app", "-type", "d", "-maxdepth", "3")
        let apps = output.components(separatedBy: "\n").filter { !$0.isEmpty }

        // Prefer simulator builds
        if let simApp = apps.first(where: { $0.contains("-iphonesimulator") }) {
            return simApp
        }
        guard let app = apps.first else {
            throw BuiltAppError.notFound(productsDir: productsDir)
        }
        return app
    }

    /// Read `CFBundleIdentifier` from an app's `Info.plist`.
    static func readBundleID(appPath: String) throws -> String {
        try ShellRunner.run(
            "/usr/libexec/PlistBuddy", "-c", "Print :CFBundleIdentifier",
            "\(appPath)/Info.plist"
        )
    }
}
