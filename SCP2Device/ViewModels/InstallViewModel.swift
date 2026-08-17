import Foundation
import Observation

/// Drives the install workflows: SCP transfer, FlashApp, and reboot.
///
/// Connection settings and the progress log live in `DeviceSession`; the SCP and
/// SSH services are injected so the workflows can be tested with mocks.
@MainActor
@Observable
final class InstallViewModel {

    private let session: DeviceSession
    private let scp: SCPServicing
    private let ssh: SSHServicing

    private var currentTask: Task<Void, Never>?
    private var currentProcess: Process?

    init(session: DeviceSession,
         scp: SCPServicing = SCPService(),
         ssh: SSHServicing = SSHService()) {
        self.session = session
        self.scp = scp
        self.ssh = ssh
    }

    // MARK: - Public Actions

    /// Toggles between starting and cancelling the full install workflow.
    func installBuild() {
        if session.isRunning && session.activeAction == .install {
            cancel()
            return
        }
        guard !session.isRunning else { return }
        begin(.install)

        currentTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.finish() }

            guard self.session.validateInputs() else { return }
            self.session.addIPToHistory(self.session.ipAddress)
            self.session.addBuildToHistory(self.session.buildPath)

            guard await self.runSCP() else { return }
            guard !Task.isCancelled else { return self.logCancelled("Install") }

            guard await self.runFlashApp() else { return }
            guard !Task.isCancelled else { return self.logCancelled("Install") }

            await self.runReboot()
            if Task.isCancelled {
                self.logCancelled("Install")
            } else {
                self.session.appendLog("\n━━━ Done ━━━\n")
            }
        }
    }

    /// Toggles between starting and cancelling an SCP-only transfer.
    func downloadBuild() {
        if session.isRunning && session.activeAction == .download {
            cancel()
            return
        }
        guard !session.isRunning else { return }
        begin(.download)

        currentTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.finish() }

            guard self.session.validateInputs() else { return }
            self.session.addIPToHistory(self.session.ipAddress)
            self.session.addBuildToHistory(self.session.buildPath)

            guard await self.runSCP() else { return }
            if Task.isCancelled {
                self.logCancelled("Transfer")
            } else {
                self.session.appendLog("\n━━━ Done ━━━\n")
            }
        }
    }

    /// Flash a build that is already on the device.
    func flashAppOnly() {
        guard !session.isRunning else { return }
        begin(nil)

        currentTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.finish() }

            guard self.session.validateIPAndDestination() else { return }
            self.session.addIPToHistory(self.session.ipAddress)
            guard await self.runFlashApp() else { return }
            self.session.appendLog("\n━━━ Done ━━━\n")
        }
    }

    /// Reboot the device only.
    func rebootOnly() {
        guard !session.isRunning else { return }
        begin(nil)

        currentTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.finish() }

            guard self.session.validateIPAndDestination() else { return }
            self.session.addIPToHistory(self.session.ipAddress)
            await self.runReboot()
            self.session.appendLog("\n━━━ Done ━━━\n")
        }
    }

    /// Cancels the in-flight install or download.
    func cancel() {
        session.appendLog("\n⚠ Cancelling…\n")
        currentProcess?.terminate()
        currentTask?.cancel()
    }

    // MARK: - Workflow steps

    /// Returns `false` if the step failed and the caller should abort.
    private func runSCP() async -> Bool {
        session.appendLog("━━━ Transferring build via SCP ━━━\n")
        do {
            let status = try await scp.transfer(
                buildPath: session.buildPath,
                deviceIP: session.ipAddress,
                destinationFolder: session.destinationFolder,
                onOutput: { [weak self] text in self?.session.appendLog(text) },
                onProgress: { [weak self] pct in self?.session.transferProgress = pct },
                onProcessStarted: { [weak self] proc in self?.currentProcess = proc }
            )
            guard status == 0 else {
                session.appendLog("✖ SCP failed with exit code \(status)\n")
                return false
            }
            session.appendLog("✔ Build transferred successfully.\n\n")
            return true
        } catch {
            session.transferProgress = nil
            session.appendLog("✖ SCP error: \(error.localizedDescription)\n")
            return false
        }
    }

    private func runFlashApp() async -> Bool {
        session.appendLog("━━━ Flashing build on device ━━━\n")
        let buildFilename = (session.buildPath as NSString).lastPathComponent

        // Llama devices require the destination folder to end in a space.
        let isLlama = await detectLlamaDevice()
        let destination = isLlama ? session.destinationFolder + " " : session.destinationFolder
        let remotePath = "\(destination)/\(buildFilename)"

        do {
            let status = try await ssh.execute(
                deviceIP: session.ipAddress,
                command: "FlashApp \(remotePath)",
                onOutput: { [weak self] text in self?.session.appendLog(text) },
                onProcessStarted: { [weak self] proc in self?.currentProcess = proc }
            )
            guard status == 0 else {
                session.appendLog("✖ FlashApp failed with exit code \(status)\n")
                return false
            }
            session.appendLog("✔ Build flashed successfully.\n\n")
            return true
        } catch {
            session.appendLog("✖ FlashApp error: \(error.localizedDescription)\n")
            return false
        }
    }

    private func runReboot() async {
        session.appendLog("━━━ Rebooting device ━━━\n")
        do {
            let status = try await ssh.execute(
                deviceIP: session.ipAddress,
                command: "/sbin/reboot",
                onOutput: { [weak self] text in self?.session.appendLog(text) },
                onProcessStarted: { [weak self] proc in self?.currentProcess = proc }
            )
            if status == 0 {
                session.appendLog("✔ Reboot command sent.\n")
            } else {
                session.appendLog("⚠ Reboot exited with code \(status) (connection may have dropped – this is expected).\n")
            }
        } catch {
            session.appendLog("⚠ Reboot error: \(error.localizedDescription) (may be expected if connection dropped).\n")
        }
    }

    /// Queries the device's prompt / hostname and returns `true` when it looks
    /// like a Llama device (which needs a trailing space on the flash path).
    private func detectLlamaDevice() async -> Bool {
        session.appendLog("━━━ Detecting device type ━━━\n")

        final class OutputBox: @unchecked Sendable { var text = "" }
        let box = OutputBox()

        _ = try? await ssh.execute(
            deviceIP: session.ipAddress,
            command: "echo \"$PS1\"; hostname; cat /etc/hostname 2>/dev/null",
            onOutput: { [weak self] text in
                box.text += text
                self?.session.appendLog(text)
            },
            onProcessStarted: { [weak self] proc in self?.currentProcess = proc }
        )

        let isLlama = box.text.lowercased().contains("llama")
        session.appendLog(isLlama
            ? "→ Llama device detected — adding trailing space to destination.\n"
            : "→ Non-Llama device — using destination as-is.\n")
        return isLlama
    }

    // MARK: - Bookkeeping

    private func begin(_ action: DeviceSession.ActiveAction?) {
        session.isRunning = true
        session.activeAction = action
    }

    private func finish() {
        session.isRunning = false
        session.activeAction = nil
        session.transferProgress = nil
        currentTask = nil
        currentProcess = nil
    }

    private func logCancelled(_ what: String) {
        session.appendLog("\n⚠ \(what) cancelled by user.\n")
    }
}
