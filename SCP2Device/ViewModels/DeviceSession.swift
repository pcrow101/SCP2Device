import Foundation
import Observation

/// Shared state for a device "session": connection settings, the progress log,
/// and which operation (if any) is currently running.
///
/// Owned by `ContentView` and injected into each feature view model so they can
/// coordinate without depending on one another.
@MainActor
@Observable
final class DeviceSession {

    /// The cancellable long-running operations.
    enum ActiveAction { case install, download }

    /// Backing store for persisted settings. Injectable so tests can use an
    /// isolated suite instead of polluting the real app defaults.
    @ObservationIgnored private let defaults: UserDefaults

    // MARK: - Persisted connection settings

    var buildPath: String {
        didSet { defaults.set(buildPath, forKey: Keys.buildPath) }
    }

    var ipAddress: String {
        didSet { defaults.set(ipAddress, forKey: Keys.ipAddress) }
    }

    var destinationFolder: String {
        didSet { defaults.set(destinationFolder, forKey: Keys.destinationFolder) }
    }

    var ipAddressHistory: [String] {
        didSet { defaults.set(ipAddressHistory, forKey: Keys.ipAddressHistory) }
    }

    var buildPathHistory: [String] {
        didSet { defaults.set(buildPathHistory, forKey: Keys.buildPathHistory) }
    }

    // MARK: - Runtime state

    var progressLog: String = ""
    var isRunning: Bool = false
    /// Which cancellable action is in progress (nil when idle or running a
    /// non-cancellable action).
    var activeAction: ActiveAction?
    /// Non-nil only while an SCP transfer is active; value is 0–100.
    var transferProgress: Double?

    // MARK: - Init

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.buildPath         = defaults.string(forKey: Keys.buildPath) ?? ""
        self.ipAddress         = defaults.string(forKey: Keys.ipAddress) ?? ""
        self.destinationFolder = defaults.string(forKey: Keys.destinationFolder) ?? "/tmp"
        self.ipAddressHistory  = defaults.stringArray(forKey: Keys.ipAddressHistory) ?? []
        self.buildPathHistory  = defaults.stringArray(forKey: Keys.buildPathHistory) ?? []
    }

    // MARK: - Log

    func appendLog(_ text: String) {
        progressLog += text
    }

    func clearLog() {
        progressLog = ""
    }

    // MARK: - Build selection

    /// Validates a dropped/selected file and makes it the current build.
    /// Returns `false` (and logs why) if the URL isn't a usable file.
    @discardableResult
    func setBuildPath(from url: URL) -> Bool {
        let path = url.isFileURL ? url.path : url.absoluteString
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
        guard exists, !isDirectory.boolValue else {
            appendLog("⚠ Drop ignored: not an existing file (\(path)).\n")
            return false
        }
        buildPath = path
        appendLog("✔ Build file set: \(path)\n")
        return true
    }

    // MARK: - History

    func addIPToHistory(_ ip: String) {
        var history = ipAddressHistory
        history.removeAll { $0 == ip }
        history.insert(ip, at: 0)
        if history.count > Self.historyLimit { history = Array(history.prefix(Self.historyLimit)) }
        ipAddressHistory = history
    }

    func addBuildToHistory(_ path: String) {
        guard !path.isEmpty else { return }
        var history = buildPathHistory
        history.removeAll { $0 == path }
        history.insert(path, at: 0)
        if history.count > Self.historyLimit { history = Array(history.prefix(Self.historyLimit)) }
        buildPathHistory = history
    }

    // MARK: - Validation

    /// Full validation: a local build file plus a reachable-looking destination.
    func validateInputs() -> Bool {
        if buildPath.isEmpty {
            appendLog("✖ Error: No build file selected.\n")
            return false
        }
        if !FileManager.default.fileExists(atPath: buildPath) {
            appendLog("✖ Error: Build file does not exist at path:\n  \(buildPath)\n")
            return false
        }
        return validateIPAndDestination()
    }

    /// Validates IP address and destination folder (no local file required).
    func validateIPAndDestination() -> Bool {
        guard validateIPOnly() else { return false }
        if destinationFolder.trimmingCharacters(in: .whitespaces).isEmpty {
            appendLog("✖ Error: Destination folder is empty.\n")
            return false
        }
        return true
    }

    /// Validates only the IP address.
    func validateIPOnly() -> Bool {
        if ipAddress.trimmingCharacters(in: .whitespaces).isEmpty {
            appendLog("✖ Error: IP address is empty.\n")
            return false
        }
        if !isValidIP(ipAddress) {
            appendLog("✖ Error: '\(ipAddress)' is not a valid IP address.\n")
            return false
        }
        return true
    }

    func isValidIP(_ ip: String) -> Bool {
        let parts = ip.split(separator: ".")
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { part in
            guard let num = Int(part), (0...255).contains(num) else { return false }
            return true
        }
    }

    // MARK: - Constants

    private static let historyLimit = 10

    private enum Keys {
        static let buildPath = "buildPath"
        static let ipAddress = "ipAddress"
        static let destinationFolder = "destinationFolder"
        static let ipAddressHistory = "ipAddressHistory"
        static let buildPathHistory = "buildPathHistory"
    }
}
