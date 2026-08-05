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

   var configText: String {
       didSet { UserDefaults.standard.set(configText, forKey: Keys.configText) }
   }

   var configSnippets: [ConfigSnippet] {
       didSet {
           if let data = try? JSONEncoder().encode(configSnippets) {
               UserDefaults.standard.set(data, forKey: Keys.configSnippets)
           }
       }
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
       self.configText = defaults.string(forKey: Keys.configText) ?? ""
       if let data = defaults.data(forKey: Keys.configSnippets),
          let snippets = try? JSONDecoder().decode([ConfigSnippet].self, from: data) {
           self.configSnippets = snippets
       } else {
           self.configSnippets = ConfigSnippet.defaults
       }
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

    /// SSH to the device, collect a set of build/version fields, and print a
    /// neatly formatted summary to the log.
    ///
    /// Fields (newest match kept if multiple):
    ///  - Image Name:          grep 'imagename:' /version.txt
    ///  - Middleware Version:  grep 'MIDDLEWARE_VERSION=' /version.txt
    ///  - VIPA Build:          grep 'viper_ipa.*widget version' /opt/logs/sky-messages.log*
    ///  - XUMO Build:          grep "app 'com.xumo.ipa' loaded: version" /opt/logs/sky-messages.log*
    ///  - OSS_VERSION:         grep 'OSS_VERSION=' /version.txt
    ///  - Essos Info:          grep '(essos) version' /opt/logs/sky-messages.log*
    ///  - Vendor Version:      grep 'VENDOR_VERSION=' /version.txt
    ///  - Application Version: grep 'APPLICATION_VERSION=' /version.txt
    ///  - PP SKY APP version:  grep 'PP SKY APP' /opt/logs/sky-messages.log*
    ///  - RDK Browser Version: grep 'com.sky.rdkbrowser.*version' /opt/logs/sky-messages.log*
    ///  - RDK Type:            grep 'FW_CLASS=' /version.txt
    ///  - Branch:              grep 'BRANCH=' /version.txt
    ///  - Build Time:          grep 'BRANCH=' /version.txt   (as specified)
    ///  - AAMP Build Info:     grep 'BRANCH=' /version.txt   (as specified)
    func showBuildInfo() {
        guard !isRunning else { return }
        guard validateIPOnly() else { return }
        isRunning = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isRunning = false; self.currentProcess = nil }
            self.addIPToHistory(self.ipAddress)
            self.appendLog("━━━ Fetching build info from device ━━━\n")

            // One shell command that emits delimited sections. Version-file
            // fields use plain grep; log-file fields use `zgrep | sort |
            // tail -n 1` so we pick the newest line by leading timestamp
            // across both plain and rotated .gz logs.
            let remoteCommand = #"""
            { \
              echo '===IMAGE==='; \
              grep -h 'imagename:' /version.txt 2>/dev/null | tail -n 1; \
              echo '===MW==='; \
              grep -h 'MIDDLEWARE_VERSION=' /version.txt 2>/dev/null | tail -n 1; \
              echo '===VIPA==='; \
              grep -h 'viper_ipa.*widget version:' /opt/logs/sky-messages.log* 2>/dev/null | tail -n 1; \
              echo '===XUMO==='; \
              grep -h "app 'com.xumo.ipa' loaded: version" /opt/logs/sky-messages.log* 2>/dev/null | tail -n 1; \
              echo '===OSS==='; \
              grep -h 'OSS_VERSION=' /version.txt 2>/dev/null | tail -n 1; \
              echo '===ESSOS==='; \
              grep -h '(essos) version' /opt/logs/sky-messages.log* 2>/dev/null | tail -n 1; \
              echo '===VENDOR==='; \
              grep -h 'VENDOR_VERSION=' /version.txt 2>/dev/null | tail -n 1; \
              echo '===APP==='; \
              grep -h 'APPLICATION_VERSION=' /version.txt 2>/dev/null | tail -n 1; \
              echo '===PPSKY==='; \
              grep -h 'PP SKY APP version' /opt/logs/sky-messages.log* 2>/dev/null | sort | tail -n 1; \
              echo '===RDKB==='; \
              grep -h 'com.sky.rdkbrowser.*version' /opt/logs/sky-messages.log* 2>/dev/null | tail -n 1; \
              echo '===RDKT==='; \
              grep -h 'FW_CLASS=' /version.txt 2>/dev/null | tail -n 1; \
              echo '===BRANCH==='; \
              grep -h 'BRANCH=' /version.txt 2>/dev/null | tail -n 1; \
              echo '===BUILDTIME==='; \
              grep -h 'BUILD_TIME=' /version.txt 2>/dev/null | tail -n 1; \
              echo '===AAMPB==='; \
              grep -h 'AAMP_BUILD_INFO:' /opt/logs/sky-messages.log* 2>/dev/null | tail -n 1; \
              echo '===END==='; \
            }
            """#

            final class Box: @unchecked Sendable { var text = "" }
            let box = Box()

            let status = (try? await self.sshService.execute(
                deviceIP: self.ipAddress,
                command: remoteCommand,
                onOutput: { text in
                    // Silently capture stdout; don't spam the log with raw output.
                    if !text.hasPrefix("▶ ") { box.text += text }
                },
                onError: { [weak self] text in self?.appendLog(text) },
                onProcessStarted: { [weak self] proc in self?.currentProcess = proc }
            )) ?? -1

            guard status == 0 else {
                self.appendLog("✖ Failed to fetch build info (exit \(status)).\n")
                return
            }

            let info = Self.parseBuildInfo(box.text)
            self.appendLog(Self.formatBuildInfo(info))
        }
    }

    // MARK: - Build Info helpers

    struct BuildInfo {
        var imageName: String?
        var middleware: String?
        var vipa: String?
        var xumo: String?
        var oss: String?
        var essos: String?
        var vendor: String?
        var application: String?
        var ppSkyApp: String?
        var rdkBrowser: String?
        var rdkType: String?
        var branch: String?
        var buildTime: String?
        var aampBuild: String?
    }

    /// Parses the delimited output produced by `showBuildInfo`'s remote command.
    static func parseBuildInfo(_ raw: String) -> BuildInfo {
        var info = BuildInfo()
        let markers = [
            "===IMAGE===", "===MW===", "===VIPA===", "===XUMO===",
            "===OSS===", "===ESSOS===", "===VENDOR===", "===APP===",
            "===PPSKY===", "===RDKB===", "===RDKT===", "===BRANCH===",
            "===BUILDTIME===", "===AAMPB===", "===END==="
        ]
        var sections: [String: String] = [:]
        var current: String? = nil
        var buffer = ""
        for line in raw.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if markers.contains(trimmed) {
                if let key = current {
                    sections[key] = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                current = trimmed
                buffer = ""
            } else if current != nil {
                if !buffer.isEmpty { buffer += "\n" }
                buffer += String(line)
            }
        }

        // Version.txt style: KEY=VALUE
        info.imageName   = extractAfter(keyword: "imagename:",
                                        in: sections["===IMAGE==="],
                                        caseInsensitive: true)
                            ?? sections["===IMAGE==="]?.nilIfEmpty
        info.middleware  = extractAfter(keyword: "MIDDLEWARE_VERSION=", in: sections["===MW==="])
                            ?? sections["===MW==="]?.nilIfEmpty
        info.oss         = extractAfter(keyword: "OSS_VERSION=",         in: sections["===OSS==="])
                            ?? sections["===OSS==="]?.nilIfEmpty
        info.vendor      = extractAfter(keyword: "VENDOR_VERSION=",      in: sections["===VENDOR==="])
                            ?? sections["===VENDOR==="]?.nilIfEmpty
        info.application = extractAfter(keyword: "APPLICATION_VERSION=", in: sections["===APP==="])
                            ?? sections["===APP==="]?.nilIfEmpty
        info.rdkType     = extractAfter(keyword: "FW_CLASS=",            in: sections["===RDKT==="])
                            ?? sections["===RDKT==="]?.nilIfEmpty
        info.branch      = extractAfter(keyword: "BRANCH=",              in: sections["===BRANCH==="])
                            ?? sections["===BRANCH==="]?.nilIfEmpty
        info.buildTime   = extractAfter(keyword: "BUILD_TIME=",              in: sections["===BUILDTIME==="])
                            ?? sections["===BUILDTIME==="]?.nilIfEmpty
        info.aampBuild   = extractAfter(keyword: "AAMP_BUILD_INFO:",              in: sections["===AAMPB==="])
                            ?? sections["===AAMPB==="]?.nilIfEmpty

        // Log lines: extract text after the version keyword (strip syslog prefix).
        info.vipa       = extractAfter(keyword: "widget version:",  in: sections["===VIPA==="])
                            ?? sections["===VIPA==="]?.nilIfEmpty
        info.xumo       = extractAfter(keyword: "loaded: version", in: sections["===XUMO==="])
                            ?? sections["===XUMO==="]?.nilIfEmpty
        info.essos      = extractAfter(keyword: "(essos) version", in: sections["===ESSOS==="])
                            ?? sections["===ESSOS==="]?.nilIfEmpty
        info.ppSkyApp   = extractAfter(keyword: "version:",      in: sections["===PPSKY==="])
                            ?? sections["===PPSKY==="]?.nilIfEmpty
        info.rdkBrowser = extractAfter(keyword: "version",         in: sections["===RDKB==="])
                            ?? sections["===RDKB==="]?.nilIfEmpty

        return info
    }

    /// Return the text after the first occurrence of `keyword` in `line`,
    /// with any surrounding double or single quotes stripped.
    private static func extractAfter(keyword: String,
                                     in line: String?,
                                     caseInsensitive: Bool = false) -> String? {
        guard let line, !line.isEmpty else { return nil }
        let options: String.CompareOptions = caseInsensitive ? [.caseInsensitive] : []
        if let range = line.range(of: keyword, options: options) {
            var value = line[range.upperBound...].trimmingCharacters(in: .whitespaces)
            // Strip surrounding matching quotes (shell KEY="value" style).
            if value.count >= 2,
               let first = value.first, let last = value.last,
               first == last, first == "\"" || first == "'" {
                value = String(value.dropFirst().dropLast())
            }
            return value.isEmpty ? nil : value
        }
        return nil
    }

    /// Format a `BuildInfo` value as a neat, monospaced summary block.
    static func formatBuildInfo(_ info: BuildInfo) -> String {
        let rows: [(String, String?)] = [
            ("Image Name",          info.imageName),
            ("Middleware Version",  info.middleware),
            ("VIPA Build",          info.vipa),
            ("XUMO Build",          info.xumo),
            ("OSS Version",         info.oss),
            ("Essos Info",          info.essos),
            ("Vendor Version",      info.vendor),
            ("Application Version", info.application),
            ("PP SKY APP version",  info.ppSkyApp),
            ("RDK Browser Version", info.rdkBrowser),
            ("RDK Type",            info.rdkType),
            ("Branch",              info.branch),
            ("Build Time",          info.buildTime),
            ("AAMP Build Info",     info.aampBuild),
        ]
        let labelWidth = rows.map { $0.0.count }.max() ?? 0
        var out = "\n┌─ Device Build Info ────────────────────────\n"
        for (label, value) in rows {
            let paddedLabel = label.padding(toLength: labelWidth, withPad: " ", startingAt: 0)
            let display = (value?.isEmpty == false) ? value! : "(not found)"
            out += "│ \(paddedLabel) : \(display)\n"
        }
        out += "└────────────────────────────────────────────\n"
        return out
    }

    /// Writes the auto-update override JSON to
    /// /opt/persistent/sky/aisettings.overrides.json on the device.
    func disableAutoUpdate() {
        guard !isRunning else { return }
        guard validateIPOnly() else { return }
        isRunning = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isRunning = false; self.currentProcess = nil }
            self.addIPToHistory(self.ipAddress)
            self.appendLog("━━━ Writing aisettings.overrides.json to device ━━━\n")

            let json = """
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

            let remotePath = "/opt/persistent/sky/aisettings.overrides.json"
            let command = "mkdir -p /opt/persistent/sky && cat > \(remotePath).tmp && mv \(remotePath).tmp \(remotePath)"

            let status = (try? await self.sshService.execute(
                deviceIP: self.ipAddress,
                command: command,
                stdin: json,
                onOutput: { [weak self] text in self?.appendLog(text) },
                onProcessStarted: { [weak self] proc in self?.currentProcess = proc }
            )) ?? -1

            if status == 0 {
                self.appendLog("✔ Auto-update override written to \(remotePath).\n")
                self.appendLog("Written JSON:\n\(json)\n")
            } else {
                self.appendLog("✖ Failed to write auto-update override (exit \(status)).\n")
            }
        }
    }

    /// Clears the progress log.
    func clearLog() {
        progressLog = ""
    }

   // MARK: - AAMP Config

    /// Appends a snippet's value to the config text, ensuring newline separation.
    func appendSnippet(_ snippet: ConfigSnippet) {
        if !configText.isEmpty && !configText.hasSuffix("\n") { configText += "\n" }
        configText += snippet.value
        if !configText.hasSuffix("\n") { configText += "\n" }
    }

    /// Appends every palette value to the config text, in order.
    func appendAllSnippets() {
        for snippet in configSnippets {
            appendSnippet(snippet)
        }
    }

   func addSnippet(value: String) {
       let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
       guard !trimmed.isEmpty else { return }
       configSnippets.append(ConfigSnippet(value: trimmed))
   }

   func updateSnippet(_ snippet: ConfigSnippet) {
       if let i = configSnippets.firstIndex(where: { $0.id == snippet.id }) {
           configSnippets[i] = snippet
       }
   }

   func deleteSnippet(_ snippet: ConfigSnippet) {
       configSnippets.removeAll { $0.id == snippet.id }
   }

   func deleteSnippets(at offsets: IndexSet) {
       configSnippets.remove(atOffsets: offsets)
   }

   func moveSnippet(from source: IndexSet, to destination: Int) {
       configSnippets.move(fromOffsets: source, toOffset: destination)
   }

   /// Reads /opt/aamp.cfg from the device into `configText` (file may not exist).
   func loadConfigFromDevice() {
       guard !isRunning else { return }
       guard validateIPOnly() else { return }
       isRunning = true
       Task { @MainActor [weak self] in
           guard let self else { return }
           defer { self.isRunning = false; self.currentProcess = nil }
           self.addIPToHistory(self.ipAddress)
           self.appendLog("━━━ Reading /opt/aamp.cfg from device ━━━\n")

           final class Box: @unchecked Sendable { var text = "" }
           let box = Box()

           let status = (try? await self.sshService.execute(
               deviceIP: self.ipAddress,
               command: "cat /opt/aamp.cfg 2>/dev/null",
               onOutput: { [weak self] text in
                   // stdout = actual file contents (skip our own command echo)
                   if !text.hasPrefix("▶ ") { box.text += text }
                   self?.appendLog(text)
               },
               onError: { [weak self] text in
                   // stderr = ssh client warnings; log only, never store in config
                   self?.appendLog(text)
               },
               onProcessStarted: { [weak self] proc in self?.currentProcess = proc }
           )) ?? -1

           if status == 0 {
               self.configText = box.text
               self.appendLog(box.text.isEmpty
                   ? "✔ No config on device yet (file empty or absent).\n"
                   : "✔ Config loaded (\(box.text.count) characters).\n")
           } else {
               self.appendLog("✖ Failed to read config (exit \(status)).\n")
           }
       }
   }

   /// Writes `configText` to /opt/aamp.cfg on the device (atomic via temp + mv).
   func saveConfigToDevice() {
       guard !isRunning else { return }
       guard validateIPOnly() else { return }
       isRunning = true
       Task { @MainActor [weak self] in
           guard let self else { return }
           defer { self.isRunning = false; self.currentProcess = nil }
           self.addIPToHistory(self.ipAddress)
           self.appendLog("━━━ Writing /opt/aamp.cfg to device ━━━\n")

           let status = (try? await self.sshService.execute(
               deviceIP: self.ipAddress,
               command: "cat > /opt/aamp.cfg.tmp && mv /opt/aamp.cfg.tmp /opt/aamp.cfg",
               stdin: self.configText,
               onOutput: { [weak self] text in self?.appendLog(text) },
               onProcessStarted: { [weak self] proc in self?.currentProcess = proc }
           )) ?? -1

           if status == 0 {
               self.appendLog("✔ Config written to /opt/aamp.cfg.\n")
           } else {
               self.appendLog("✖ Failed to write config (exit \(status)).\n")
           }
       }
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

   /// Validates only the IP address (config actions don't need a build file).
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
       static let configText = "configText"
       static let configSnippets = "configSnippets"
    }
}

private extension String {
    /// Returns nil when the string is empty (after being unwrapped from an
    /// Optional via `?.nilIfEmpty`); otherwise returns self.
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
