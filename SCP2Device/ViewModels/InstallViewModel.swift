import Foundation
import Observation
import SwiftUI

/// Drives the three-part install workflow and persists user settings via UserDefaults.
@MainActor
@Observable
final class InstallViewModel {

    // MARK: - Persisted User Inputs

    var buildPath: String {
        didSet { UserDefaults.standard.set(buildPath, forKey: Keys.buildPath) }
    }

    var ipAddress: String {
        didSet { UserDefaults.standard.set(ipAddress, forKey: Keys.ipAddress) }
    }

    var destinationFolder: String {
        didSet { UserDefaults.standard.set(destinationFolder, forKey: Keys.destinationFolder) }
    }

    var ipAddressHistory: [String] {
        didSet { UserDefaults.standard.set(ipAddressHistory, forKey: Keys.ipAddressHistory) }
    }

    var buildPathHistory: [String] {
        didSet { UserDefaults.standard.set(buildPathHistory, forKey: Keys.buildPathHistory) }
    }

    // MARK: - UI State

    var progressLog: String = ""
    var isRunning: Bool = false
    /// Non-nil only while an SCP transfer is active; value is 0–100.
    var transferProgress: Double? = nil

    // MARK: - Services

    private let scpService = SCPService()
    private let sshService = SSHService()

    // MARK: - Init

    init() {
        let defaults = UserDefaults.standard
        self.buildPath = defaults.string(forKey: Keys.buildPath) ?? ""
        self.ipAddress = defaults.string(forKey: Keys.ipAddress) ?? ""
        self.destinationFolder = defaults.string(forKey: Keys.destinationFolder) ?? "/tmp"
        self.ipAddressHistory = defaults.stringArray(forKey: Keys.ipAddressHistory) ?? []
        self.buildPathHistory = defaults.stringArray(forKey: Keys.buildPathHistory) ?? []
    }

    // MARK: - Public Actions

    /// Runs the full install workflow: SCP → FlashApp (if checked) → Reboot (if checked).
    func installBuild() {
        guard !isRunning else { return }
        isRunning = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isRunning = false }
            guard self.validateInputs() else { return }
            self.addIPToHistory(self.ipAddress)
            self.addBuildToHistory(self.buildPath)
            guard (try? await self.runSCP()) == true else { return }
            guard (try? await self.runFlashApp()) == true else { return }
            try? await self.runReboot()
            self.appendLog("\n━━━ Done ━━━\n")
        }
    }

    /// SCP the build onto the device only.
    func downloadBuild() {
        guard !isRunning else { return }
        isRunning = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isRunning = false }
            guard self.validateInputs() else { return }
            self.addIPToHistory(self.ipAddress)
            self.addBuildToHistory(self.buildPath)
            guard (try? await self.runSCP()) == true else { return }
            self.appendLog("\n━━━ Done ━━━\n")
        }
    }

    /// Flash the build on the device only (build must already be on device).
    func flashAppOnly() {
        guard !isRunning else { return }
        isRunning = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isRunning = false }
            guard self.validateIPAndDestination() else { return }
            self.addIPToHistory(self.ipAddress)
            guard (try? await self.runFlashApp()) == true else { return }
            self.appendLog("\n━━━ Done ━━━\n")
        }
    }

    /// Reboot the device only.
    func rebootOnly() {
        guard !isRunning else { return }
        isRunning = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isRunning = false }
            guard self.validateIPAndDestination() else { return }
            self.addIPToHistory(self.ipAddress)
            try? await self.runReboot()
            self.appendLog("\n━━━ Done ━━━\n")
        }
    }

    /// Clears the progress log.
    func clearLog() {
        progressLog = ""
    }

    // MARK: - Private Workflow Steps

    /// Returns `false` if the step failed and the caller should abort.
    @discardableResult
    private func runSCP() async throws -> Bool {
        appendLog("━━━ Transferring build via SCP ━━━\n")
        do {
            let status = try await scpService.transfer(
                buildPath: buildPath,
                deviceIP: ipAddress,
                destinationFolder: destinationFolder,
                onOutput: { [weak self] text in self?.appendLog(text) },
                onProgress: { [weak self] pct in self?.transferProgress = pct }
            )
            if status != 0 {
                appendLog("✖ SCP failed with exit code \(status)\n")
                return false
            }
            appendLog("✔ Build transferred successfully.\n\n")
            return true
        } catch {
            transferProgress = nil
            appendLog("✖ SCP error: \(error.localizedDescription)\n")
            return false
        }
    }

    @discardableResult
    private func runFlashApp() async throws -> Bool {
        appendLog("━━━ Flashing build on device ━━━\n")
        let buildFilename = (buildPath as NSString).lastPathComponent
        let remotePath = "\(destinationFolder)/\(buildFilename)"
        do {
            let status = try await sshService.execute(
                deviceIP: ipAddress,
                command: "FlashApp \(remotePath)",
                onOutput: { [weak self] text in self?.appendLog(text) }
            )
            if status != 0 {
                appendLog("✖ FlashApp failed with exit code \(status)\n")
                return false
            }
            appendLog("✔ Build flashed successfully.\n\n")
            return true
        } catch {
            appendLog("✖ FlashApp error: \(error.localizedDescription)\n")
            return false
        }
    }

    private func runReboot() async throws {
        appendLog("━━━ Rebooting device ━━━\n")
        do {
            let status = try await sshService.execute(
                deviceIP: ipAddress,
                command: "/sbin/reboot",
                onOutput: { [weak self] text in self?.appendLog(text) }
            )
            if status == 0 {
                appendLog("✔ Reboot command sent.\n")
            } else {
                appendLog("⚠ Reboot exited with code \(status) (connection may have dropped – this is expected).\n")
            }
        } catch {
            appendLog("⚠ Reboot error: \(error.localizedDescription) (may be expected if connection dropped).\n")
        }
    }

    // MARK: - Helpers

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

    /// Validates only IP address and destination folder (no local file required).
    func validateIPAndDestination() -> Bool {
        if ipAddress.trimmingCharacters(in: .whitespaces).isEmpty {
            appendLog("✖ Error: IP address is empty.\n")
            return false
        }
        if !isValidIP(ipAddress) {
            appendLog("✖ Error: '\(ipAddress)' is not a valid IP address.\n")
            return false
        }
        if destinationFolder.trimmingCharacters(in: .whitespaces).isEmpty {
            appendLog("✖ Error: Destination folder is empty.\n")
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

    func addIPToHistory(_ ip: String) {
        var history = ipAddressHistory
        history.removeAll { $0 == ip }
        history.insert(ip, at: 0)
        if history.count > 10 { history = Array(history.prefix(10)) }
        ipAddressHistory = history
    }

    func addBuildToHistory(_ path: String) {
        guard !path.isEmpty else { return }
        var history = buildPathHistory
        history.removeAll { $0 == path }
        history.insert(path, at: 0)
        if history.count > 10 { history = Array(history.prefix(10)) }
        buildPathHistory = history
    }

    func appendLog(_ text: String) {
        progressLog += text
    }

    // MARK: - UserDefaults Keys

    private enum Keys {
        static let buildPath = "buildPath"
        static let ipAddress = "ipAddress"
        static let destinationFolder = "destinationFolder"
        static let ipAddressHistory = "ipAddressHistory"
        static let buildPathHistory = "buildPathHistory"
    }
}
