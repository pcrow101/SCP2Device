import Foundation
import Observation

/// Device inspection and one-shot device tweaks: reading build/version info and
/// disabling dynamic auto-updates.
///
/// Note this view model publishes a `BuildInfo` *model* rather than a formatted
/// string — rendering is the view's job (`BuildInfoReport`).
@MainActor
@Observable
final class DeviceInfoViewModel {

    private let session: DeviceSession
    private let ssh: SSHServicing
    private var currentProcess: Process?

    /// The most recently fetched build info, or `nil` if none has been read yet.
    private(set) var latestBuildInfo: BuildInfo?

    /// Increments on every successful fetch, even if the resulting `BuildInfo`
    /// is identical to the previous one.
    ///
    /// `BuildInfo` is `Equatable`, and views observe `latestBuildInfo` via
    /// `onChange` to know when to log a formatted report. `onChange` only
    /// fires when the *value* changes — so if the device's build info is
    /// unchanged between two fetches, a second press of "Build Info" would
    /// silently produce no log output. Observing this counter instead
    /// guarantees every fetch is reported, regardless of whether the content
    /// happens to match the previous result.
    private(set) var buildInfoFetchCount: Int = 0

    private static let overridesPath = "/opt/persistent/sky/aisettings.overrides.json"

    init(session: DeviceSession, ssh: SSHServicing = SSHService()) {
        self.session = session
        self.ssh = ssh
    }

    // MARK: - Build info

    /// SSHes to the device, collects the version fields, and publishes them via
    /// `latestBuildInfo`.
    func showBuildInfo() {
        guard !session.isRunning, session.validateIPOnly() else { return }
        session.isRunning = true

        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.session.isRunning = false; self.currentProcess = nil }

            self.session.addIPToHistory(self.session.ipAddress)
            self.session.appendLog("━━━ Fetching build info from device ━━━\n")

            final class Box: @unchecked Sendable { var text = "" }
            let box = Box()

            let status = (try? await self.ssh.execute(
                deviceIP: self.session.ipAddress,
                command: BuildInfo.remoteCommand,
                onOutput: { text in
                    // Capture stdout silently; don't spam the log with raw output.
                    if !text.hasPrefix("▶ ") { box.text += text }
                },
                onError: { [weak self] text in self?.session.appendLog(text) },
                onProcessStarted: { [weak self] proc in self?.currentProcess = proc }
            )) ?? -1

            guard status == 0 else {
                self.session.appendLog("✖ Failed to fetch build info (exit \(status)).\n")
                return
            }

            self.latestBuildInfo = BuildInfo.parse(box.text)
            self.buildInfoFetchCount += 1
        }
    }

    // MARK: - Auto update

    /// Writes the auto-update override JSON to the device.
    func disableAutoUpdate() {
        guard !session.isRunning, session.validateIPOnly() else { return }
        session.isRunning = true

        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.session.isRunning = false; self.currentProcess = nil }

            self.session.addIPToHistory(self.session.ipAddress)
            self.session.appendLog("━━━ Writing aisettings.overrides.json to device ━━━\n")

            let json = Self.autoUpdateOverrideJSON
            let path = Self.overridesPath
            let command = "mkdir -p \((path as NSString).deletingLastPathComponent) "
                        + "&& cat > \(path).tmp && mv \(path).tmp \(path)"

            let status = (try? await self.ssh.execute(
                deviceIP: self.session.ipAddress,
                command: command,
                stdin: json,
                onOutput: { [weak self] text in self?.session.appendLog(text) },
                onProcessStarted: { [weak self] proc in self?.currentProcess = proc }
            )) ?? -1

            if status == 0 {
                self.session.appendLog("✔ Auto-update override written to \(path).\n")
                self.session.appendLog("Written JSON:\n\(json)\n")
            } else {
                self.session.appendLog("✖ Failed to write auto-update override (exit \(status)).\n")
            }
        }
    }

    static let autoUpdateOverrideJSON = """
    {
      "dynamicIUIupdate": {
        "enable": false,
        "checkOnStartup": false
      },
      "apps": {
        "extraEnvVars": [
          "AAMP_CFG_TEXT=info=true,progress=true,monitorAV=true"
        ]
      }
    }
    """
}
