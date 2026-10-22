import Foundation

/// Every on-disk location WideAwake uses. The whole tree can be relocated with
/// the `WIDEAWAKE_HOME` environment variable (tests, and `backstop.sh` honours
/// the same variable with the same layout).
///
/// Default layout:
///   ~/Library/Application Support/WideAwake/{session.json,state.json,config.json,backstop.sh}
///   ~/Library/Logs/WideAwake/{wideawake.log,handoffs.log}
///   ~/Library/LaunchAgents/dev.nazeeh.wideawake.recovery.plist
///
/// With WIDEAWAKE_HOME=/x:
///   /x/{session.json,state.json,config.json,backstop.sh}
///   /x/Logs/{wideawake.log,handoffs.log}
///   /x/LaunchAgents/dev.nazeeh.wideawake.recovery.plist
struct Paths: Sendable, Equatable {
    static let environmentKey = "WIDEAWAKE_HOME"
    static let backstopLabel = "dev.nazeeh.wideawake.recovery"
    static let bundleIdentifier = "dev.nazeeh.wideawake"

    let appSupport: URL
    let logs: URL
    let launchAgents: URL

    init(appSupport: URL, logs: URL, launchAgents: URL) {
        self.appSupport = appSupport
        self.logs = logs
        self.launchAgents = launchAgents
    }

    /// Relocated layout rooted at one directory (used for WIDEAWAKE_HOME).
    init(root: URL) {
        self.init(
            appSupport: root,
            logs: root.appendingPathComponent("Logs", isDirectory: true),
            launchAgents: root.appendingPathComponent("LaunchAgents", isDirectory: true)
        )
    }

    /// The standard per-user layout under ~/Library.
    static var standard: Paths {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let library = home.appendingPathComponent("Library", isDirectory: true)
        return Paths(
            appSupport: library.appendingPathComponent("Application Support/WideAwake", isDirectory: true),
            logs: library.appendingPathComponent("Logs/WideAwake", isDirectory: true),
            launchAgents: library.appendingPathComponent("LaunchAgents", isDirectory: true)
        )
    }

    /// `WIDEAWAKE_HOME` if set, else `standard`.
    static func fromEnvironment(_ env: [String: String] = ProcessInfo.processInfo.environment) -> Paths {
        if let root = env[environmentKey], !root.isEmpty {
            return Paths(root: URL(fileURLWithPath: root, isDirectory: true))
        }
        return .standard
    }

    var sessionFile: URL { appSupport.appendingPathComponent("session.json") }
    var stateFile: URL { appSupport.appendingPathComponent("state.json") }
    var configFile: URL { appSupport.appendingPathComponent("config.json") }
    /// Installed copy of scripts/backstop.sh, placed there by install.sh.
    var backstopScript: URL { appSupport.appendingPathComponent("backstop.sh") }
    /// flock(2) file shared with backstop.sh (`lockf -k` on the same path).
    /// Created once, never unlinked, so both sides lock the same inode.
    var recoveryLock: URL { appSupport.appendingPathComponent(".recovery.lock") }
    /// Written by scripts/simulate-lid.sh ("closed" or "open") to drive the
    /// lid-close action path without touching the hinge. See LidSimulation.
    var simulateLidFile: URL { appSupport.appendingPathComponent("simulate-lid") }

    var logFile: URL { logs.appendingPathComponent("wideawake.log") }
    var handoffsLog: URL { logs.appendingPathComponent("handoffs.log") }

    var backstopPlist: URL { launchAgents.appendingPathComponent("\(Paths.backstopLabel).plist") }

    /// Create every directory WideAwake writes into.
    func createDirectories() throws {
        for dir in [appSupport, logs, launchAgents] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }
}
