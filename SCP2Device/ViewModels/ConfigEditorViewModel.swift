import Foundation
import Observation
import SwiftUI

/// Owns the `/opt/aamp.cfg` editor: the config text, the reusable settings
/// palette, and reading/writing the file on the device.
@MainActor
@Observable
final class ConfigEditorViewModel {

    private let session: DeviceSession
    private let ssh: SSHServicing
    private var currentProcess: Process?

    /// Backing store for persisted settings. Injectable so tests can use an
    /// isolated suite instead of polluting the real app defaults.
    @ObservationIgnored private let defaults: UserDefaults

    /// Remote path of the AAMP config file.
    private static let configPath = "/opt/aamp.cfg"

    // MARK: - Persisted state

    var configText: String {
        didSet { defaults.set(configText, forKey: Keys.configText) }
    }

    var configSnippets: [ConfigSnippet] {
        didSet {
            if let data = try? JSONEncoder().encode(configSnippets) {
                defaults.set(data, forKey: Keys.configSnippets)
            }
        }
    }

    // MARK: - Derived state (for the view)

    var deviceIP: String { session.ipAddress }
    var isRunning: Bool { session.isRunning }

    // MARK: - Init

    init(session: DeviceSession,
         ssh: SSHServicing = SSHService(),
         defaults: UserDefaults = .standard) {
        self.session = session
        self.ssh = ssh
        self.defaults = defaults

        self.configText = defaults.string(forKey: Keys.configText) ?? ""
        if let data = defaults.data(forKey: Keys.configSnippets),
           let snippets = try? JSONDecoder().decode([ConfigSnippet].self, from: data) {
            self.configSnippets = snippets
        } else {
            self.configSnippets = ConfigSnippet.defaults
        }
    }

    // MARK: - Palette

    /// Appends a snippet's value to the config text, ensuring newline separation.
    func appendSnippet(_ snippet: ConfigSnippet) {
        if !configText.isEmpty && !configText.hasSuffix("\n") { configText += "\n" }
        configText += snippet.value
        if !configText.hasSuffix("\n") { configText += "\n" }
    }

    /// Appends every palette value to the config text, in order.
    func appendAllSnippets() {
        configSnippets.forEach(appendSnippet)
    }

    func addSnippet(value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        configSnippets.append(ConfigSnippet(value: trimmed))
    }

    func updateSnippet(_ snippet: ConfigSnippet) {
        if let index = configSnippets.firstIndex(where: { $0.id == snippet.id }) {
            configSnippets[index] = snippet
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

    // MARK: - Device I/O

    /// Reads the config from the device into `configText` (file may not exist).
    func loadConfigFromDevice() {
        guard !session.isRunning, session.validateIPOnly() else { return }
        session.isRunning = true

        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.session.isRunning = false; self.currentProcess = nil }

            self.session.addIPToHistory(self.session.ipAddress)
            self.session.appendLog("━━━ Reading \(Self.configPath) from device ━━━\n")

            final class Box: @unchecked Sendable { var text = "" }
            let box = Box()

            let status = (try? await self.ssh.execute(
                deviceIP: self.session.ipAddress,
                command: "cat \(Self.configPath) 2>/dev/null",
                onOutput: { [weak self] text in
                    // stdout = actual file contents (skip our own command echo)
                    if !text.hasPrefix("▶ ") { box.text += text }
                    self?.session.appendLog(text)
                },
                onError: { [weak self] text in
                    // stderr = ssh client warnings; log only, never store in config
                    self?.session.appendLog(text)
                },
                onProcessStarted: { [weak self] proc in self?.currentProcess = proc }
            )) ?? -1

            guard status == 0 else {
                self.session.appendLog("✖ Failed to read config (exit \(status)).\n")
                return
            }

            self.configText = box.text
            self.session.appendLog(box.text.isEmpty
                ? "✔ No config on device yet (file empty or absent).\n"
                : "✔ Config loaded (\(box.text.count) characters).\n")
        }
    }

    /// Writes `configText` to the device atomically (temp file + rename).
    func saveConfigToDevice() {
        guard !session.isRunning, session.validateIPOnly() else { return }
        session.isRunning = true

        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.session.isRunning = false; self.currentProcess = nil }

            self.session.addIPToHistory(self.session.ipAddress)
            self.session.appendLog("━━━ Writing \(Self.configPath) to device ━━━\n")

            let path = Self.configPath
            let status = (try? await self.ssh.execute(
                deviceIP: self.session.ipAddress,
                command: "cat > \(path).tmp && mv \(path).tmp \(path)",
                stdin: self.configText,
                onOutput: { [weak self] text in self?.session.appendLog(text) },
                onProcessStarted: { [weak self] proc in self?.currentProcess = proc }
            )) ?? -1

            if status == 0 {
                self.session.appendLog("✔ Config written to \(path).\n")
            } else {
                self.session.appendLog("✖ Failed to write config (exit \(status)).\n")
            }
        }
    }

    // MARK: - Keys

    private enum Keys {
        static let configText = "configText"
        static let configSnippets = "configSnippets"
    }
}
