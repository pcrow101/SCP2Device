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

    enum ActiveAction { case install, download }

    var progressLog: String = ""
    var isRunning: Bool = false
    /// Which cancellable action is currently in progress (nil when idle).
    var activeAction: ActiveAction?
    /// Non-nil only while an SCP transfer is active; value is 0–100.
    var transferProgress: Double? = nil

    // MARK: - Cancellation

    private var currentTask: Task<Void, Never>?
    private var currentProcess: Process?

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

    /// Toggles between starting and cancelling the full install workflow.
    func installBuild() {
        if isRunning && activeAction == .install {
            cancelInstall()
            return
        }
        guard !isRunning else { return }
        isRunning = true
        activeAction = .install
        currentTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.isRunning = false
                self.activeAction = nil
                self.currentTask = nil
                self.currentProcess = nil
            }
            guard self.validateInputs() else { return }
            self.addIPToHistory(self.ipAddress)
            self.addBuildToHistory(self.buildPath)

            guard (try? await self.runSCP()) == true else { return }
            guard !Task.isCancelled else {
                self.appendLog("\n⚠ Install cancelled by user.\n")
                return
            }

            guard (try? await self.runFlashApp()) == true else { return }
            guard !Task.isCancelled else {
                self.appendLog("\n⚠ Install cancelled by user.\n")
                return
            }

            try? await self.runReboot()
            if !Task.isCancelled {
                self.appendLog("\n━━━ Done ━━━\n")
            } else {
                self.appendLog("\n⚠ Install cancelled by user.\n")
            }
        }
    }

    /// Cancels any in-flight install workflow.
    func cancelInstall() {
        appendLog("\n⚠ Cancelling…\n")
        currentProcess?.terminate()
        currentTask?.cancel()
    }

    /// Toggles between starting and cancelling an SCP-only transfer.
    func downloadBuild() {
        if isRunning && activeAction == .download {
            cancelInstall()
            return
        }
        guard !isRunning else { return }
        isRunning = true
        activeAction = .download
        currentTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.isRunning = false
                self.activeAction = nil
                self.currentTask = nil
                self.currentProcess = nil
            }
            guard self.validateInputs() else { return }
            self.addIPToHistory(self.ipAddress)
            self.addBuildToHistory(self.buildPath)
            guard (try? await self.runSCP()) == true else { return }
            if !Task.isCancelled {
                self.appendLog("\n━━━ Done ━━━\n")
            } else {
                self.appendLog("\n⚠ Transfer cancelled by user.\n")
            }
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
                onProgress: { [weak self] pct in self?.transferProgress = pct },
                onProcessStarted: { [weak self] proc in self?.currentProcess = proc }
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

        // Llama devices require the destination folder to end in a space.
        let isLlama = await detectLlamaDevice()
        let effectiveDestination = isLlama ? destinationFolder + " " : destinationFolder
        let remotePath = "\(effectiveDestination)/\(buildFilename)"
        do {
            let status = try await sshService.execute(
                deviceIP: ipAddress,
                command: "FlashApp \(remotePath)",
                onOutput: { [weak self] text in self?.appendLog(text) },
                onProcessStarted: { [weak self] proc in self?.currentProcess = proc }
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
                onOutput: { [weak self] text in self?.appendLog(text) },
                onProcessStarted: { [weak self] proc in self?.currentProcess = proc }
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

    /// Queries the device's command prompt / hostname over SSH and returns `true`
    /// if it contains "llama" (case-insensitive). Llama devices require the flash
    /// destination folder to end in a trailing space.
    private func detectLlamaDevice() async -> Bool {
        appendLog("━━━ Detecting device type ━━━\n")

        // Reference box so the @Sendable output callback can accumulate text.
        final class OutputBox: @unchecked Sendable { var text = "" }
        let box = OutputBox()

        _ = try? await sshService.execute(
            deviceIP: ipAddress,
            command: "echo \"$PS1\"; hostname; cat /etc/hostname 2>/dev/null",
            onOutput: { [weak self] text in
                box.text += text
                self?.appendLog(text)
            },
            onProcessStarted: { [weak self] proc in self?.currentProcess = proc }
        )

        let isLlama = box.text.lowercased().contains("llama")
        appendLog(isLlama
            ? "→ Llama device detected — adding trailing space to destination.\n"
            : "→ Non-Llama device — using destination as-is.\n")
        return isLlama
    }

    func validateInputs() -> Bool {        if buildPath.isEmpty {
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
