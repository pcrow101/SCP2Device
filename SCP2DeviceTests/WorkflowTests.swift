import Testing
import Foundation
@testable import SCP2Device

// MARK: - Mocks
//
// These exist only because the view models now depend on `SCPServicing` /
// `SSHServicing` rather than the concrete services. Before dependency
// injection, none of the workflow tests below were possible.

final class MockSCPService: SCPServicing, @unchecked Sendable {
    private let lock = NSLock()
    private var _transferCount = 0
    private var _lastDestination: String?

    /// Exit status the mock should return.
    var exitStatus: Int32 = 0
    /// When true the transfer suspends until the enclosing Task is cancelled,
    /// letting tests exercise the cancel path mid-transfer.
    var blockUntilCancelled = false

    var transferCount: Int { lock.withLock { _transferCount } }
    var lastDestination: String? { lock.withLock { _lastDestination } }

    func transfer(
        buildPath: String,
        deviceIP: String,
        destinationFolder: String,
        onOutput: @MainActor @escaping @Sendable (String) -> Void,
        onProgress: @MainActor @escaping @Sendable (Double?) -> Void,
        onProcessStarted: @MainActor @escaping @Sendable (Process) -> Void
    ) async throws -> Int32 {
        lock.withLock {
            _transferCount += 1
            _lastDestination = destinationFolder
        }
        if blockUntilCancelled {
            // Throws CancellationError when the enclosing Task is cancelled.
            try await Task.sleep(for: .seconds(30))
        }
        return exitStatus
    }
}

final class MockSSHService: SSHServicing, @unchecked Sendable {
    private let lock = NSLock()
    private var _commands: [String] = []

    /// Exit status the mock should return.
    var exitStatus: Int32 = 0
    /// Text delivered to `onOutput` for every command (used for Llama detection).
    var stdout: String = ""
    /// Text delivered to `onError` (stderr) when a caller provides an onError sink.
    var stderr: String = ""

    var commands: [String] { lock.withLock { _commands } }

    func execute(
        deviceIP: String,
        command: String,
        stdin: String?,
        onOutput: @MainActor @escaping @Sendable (String) -> Void,
        onError: (@MainActor @Sendable (String) -> Void)?,
        onProcessStarted: @MainActor @escaping @Sendable (Process) -> Void
    ) async throws -> Int32 {
        lock.withLock { _commands.append(command) }
        let out = stdout
        if !out.isEmpty {
            await MainActor.run { onOutput(out) }
        }
        let err = stderr
        if !err.isEmpty, let onError {
            await MainActor.run { onError(err) }
        }
        return exitStatus
    }
}

// MARK: - Helpers

@MainActor
private func waitUntilIdle(_ session: DeviceSession) async throws {
    let deadline = ContinuousClock.now + .seconds(5)
    while session.isRunning && ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(5))
    }
}

/// Polls until `condition` is true or the timeout elapses.
@MainActor
private func waitUntil(timeout: Duration = .seconds(5),
                       _ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now + timeout
    while !condition() && ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(5))
    }
}

@MainActor
private func makeSession(ip: String = "10.0.0.1",
                         build: String = "/bin/ls",
                         destination: String = "/tmp") -> DeviceSession {
    // Isolated defaults so tests never pollute the real app's build/IP history.
    let session = DeviceSession(defaults: makeTestDefaults())
    session.ipAddress = ip
    session.buildPath = build
    session.destinationFolder = destination
    session.progressLog = ""
    return session
}

// MARK: - Install Workflow

@Suite("Install Workflow")
struct InstallWorkflowTests {

    @Test("Install runs SCP, FlashApp, then reboot")
    @MainActor func fullWorkflow() async throws {
        let session = makeSession()
        let scp = MockSCPService()
        let ssh = MockSSHService()
        let vm = InstallViewModel(session: session, scp: scp, ssh: ssh)

        vm.installBuild()
        try await waitUntilIdle(session)

        #expect(scp.transferCount == 1)
        // Llama detection, FlashApp, reboot
        #expect(ssh.commands.count == 3)
        #expect(ssh.commands[1] == "FlashApp /tmp/ls")
        #expect(ssh.commands[2] == "/sbin/reboot")
        #expect(session.progressLog.contains("Done"))
    }

    @Test("Failed SCP aborts before flashing")
    @MainActor func scpFailureAborts() async throws {
        let session = makeSession()
        let scp = MockSCPService()
        scp.exitStatus = 1
        let ssh = MockSSHService()
        let vm = InstallViewModel(session: session, scp: scp, ssh: ssh)

        vm.installBuild()
        try await waitUntilIdle(session)

        #expect(scp.transferCount == 1)
        #expect(ssh.commands.isEmpty)   // never got as far as flashing
        #expect(session.progressLog.contains("SCP failed"))
    }

    @Test("Invalid input runs nothing")
    @MainActor func invalidInputRunsNothing() async throws {
        let session = makeSession(ip: "999.999.999.999")
        let scp = MockSCPService()
        let ssh = MockSSHService()
        let vm = InstallViewModel(session: session, scp: scp, ssh: ssh)

        vm.installBuild()
        try await waitUntilIdle(session)

        #expect(scp.transferCount == 0)
        #expect(ssh.commands.isEmpty)
        #expect(session.progressLog.contains("not a valid IP address"))
    }

    @Test("Download Only transfers without flashing or rebooting")
    @MainActor func downloadOnly() async throws {
        let session = makeSession()
        let scp = MockSCPService()
        let ssh = MockSSHService()
        let vm = InstallViewModel(session: session, scp: scp, ssh: ssh)

        vm.downloadBuild()
        try await waitUntilIdle(session)

        #expect(scp.transferCount == 1)
        #expect(ssh.commands.isEmpty)
    }

    @Test("Reboot Only sends just the reboot command")
    @MainActor func rebootOnly() async throws {
        let session = makeSession()
        let scp = MockSCPService()
        let ssh = MockSSHService()
        let vm = InstallViewModel(session: session, scp: scp, ssh: ssh)

        vm.rebootOnly()
        try await waitUntilIdle(session)

        #expect(scp.transferCount == 0)
        #expect(ssh.commands == ["/sbin/reboot"])
    }

    @Test("Llama devices get a trailing space on the flash path")
    @MainActor func llamaTrailingSpace() async throws {
        let session = makeSession()
        let scp = MockSCPService()
        let ssh = MockSSHService()
        ssh.stdout = "root@llama-device:~#"
        let vm = InstallViewModel(session: session, scp: scp, ssh: ssh)

        vm.flashAppOnly()
        try await waitUntilIdle(session)

        // Detection command first, then the flash with "/tmp " (trailing space)
        #expect(ssh.commands.last == "FlashApp /tmp /ls")
        #expect(session.progressLog.contains("Llama device detected"))
    }

    @Test("Session is left idle after a run")
    @MainActor func sessionResets() async throws {
        let session = makeSession()
        let vm = InstallViewModel(session: session,
                                  scp: MockSCPService(),
                                  ssh: MockSSHService())

        vm.downloadBuild()
        #expect(session.isRunning)          // synchronously busy
        try await waitUntilIdle(session)

        #expect(!session.isRunning)
        #expect(session.activeAction == nil)
        #expect(session.transferProgress == nil)
    }
}

// MARK: - Device Info

@Suite("Device Info")
struct DeviceInfoTests {

    @Test("Build info is published as a model, not a string")
    @MainActor func publishesModel() async throws {
        let session = makeSession()
        let ssh = MockSSHService()
        ssh.stdout = """
        ===IMAGE===
        imagename: TEST_BUILD_123
        ===MW===
        MIDDLEWARE_VERSION="1.2.3"
        ===END===
        """
        let vm = DeviceInfoViewModel(session: session, ssh: ssh)

        vm.showBuildInfo()
        try await waitUntilIdle(session)

        #expect(vm.latestBuildInfo?.imageName == "TEST_BUILD_123")
        #expect(vm.latestBuildInfo?.middleware == "1.2.3")
        #expect(vm.buildInfoFetchCount == 1)
    }

    @Test("Repeated identical fetches still increment the fetch count")
    @MainActor func repeatedFetchAlwaysIncrementsCount() async throws {
        // Regression test: BuildInfo is Equatable, and the view observes
        // `buildInfoFetchCount` (not `latestBuildInfo` directly) so that two
        // consecutive fetches with identical results are both reported rather
        // than the second being silently swallowed by onChange's equality check.
        let session = makeSession()
        let ssh = MockSSHService()
        ssh.stdout = """
        ===IMAGE===
        imagename: SAME_BUILD
        ===END===
        """
        let vm = DeviceInfoViewModel(session: session, ssh: ssh)

        vm.showBuildInfo()
        try await waitUntilIdle(session)
        #expect(vm.buildInfoFetchCount == 1)
        let firstInfo = vm.latestBuildInfo

        vm.showBuildInfo()
        try await waitUntilIdle(session)
        #expect(vm.buildInfoFetchCount == 2)
        #expect(vm.latestBuildInfo == firstInfo)   // identical content...
        // ...but the counter still advanced, which is what the view relies on.
    }

    @Test("Disable Auto Update writes the override file")
    @MainActor func disableAutoUpdate() async throws {
        let session = makeSession()
        let ssh = MockSSHService()
        let vm = DeviceInfoViewModel(session: session, ssh: ssh)

        vm.disableAutoUpdate()
        try await waitUntilIdle(session)

        let command = try #require(ssh.commands.first)
        #expect(command.contains("mkdir -p /opt/persistent/sky"))
        #expect(command.contains("aisettings.overrides.json"))
        #expect(session.progressLog.contains("Auto-update override written"))
    }
}

// MARK: - Config Editor

@Suite("Config Editor")
struct ConfigEditorTests {

    @Test("Appending a snippet keeps newline separation")
    @MainActor func appendSnippet() {
        let vm = ConfigEditorViewModel(session: makeSession(),
                                       ssh: MockSSHService(),
                                       defaults: makeTestDefaults())
        vm.configText = ""
        vm.appendSnippet(ConfigSnippet(value: "info=true"))
        vm.appendSnippet(ConfigSnippet(value: "progress=true"))
        #expect(vm.configText == "info=true\nprogress=true\n")
    }

    @Test("Snippets can be reordered and deleted")
    @MainActor func reorderAndDelete() {
        let vm = ConfigEditorViewModel(session: makeSession(),
                                       ssh: MockSSHService(),
                                       defaults: makeTestDefaults())
        vm.configSnippets = [
            ConfigSnippet(value: "a"),
            ConfigSnippet(value: "b"),
            ConfigSnippet(value: "c")
        ]
        vm.moveSnippet(from: IndexSet(integer: 2), to: 0)
        #expect(vm.configSnippets.map(\.value) == ["c", "a", "b"])

        vm.deleteSnippets(at: IndexSet(integer: 0))
        #expect(vm.configSnippets.map(\.value) == ["a", "b"])
    }

    @Test("Blank snippet values are ignored")
    @MainActor func ignoresBlankSnippet() {
        let vm = ConfigEditorViewModel(session: makeSession(),
                                       ssh: MockSSHService(),
                                       defaults: makeTestDefaults())
        vm.configSnippets = []
        vm.addSnippet(value: "   ")
        #expect(vm.configSnippets.isEmpty)
    }

    @Test("Saving writes the config atomically")
    @MainActor func saveUsesAtomicWrite() async throws {
        let session = makeSession()
        let ssh = MockSSHService()
        let vm = ConfigEditorViewModel(session: session, ssh: ssh, defaults: makeTestDefaults())
        vm.configText = "info=true\n"

        vm.saveConfigToDevice()
        try await waitUntilIdle(session)

        let command = try #require(ssh.commands.first)
        #expect(command.contains("cat > /opt/aamp.cfg.tmp"))
        #expect(command.contains("mv /opt/aamp.cfg.tmp /opt/aamp.cfg"))
    }
}

// MARK: - BuildInfo Parsing

@Suite("BuildInfo Parsing")
struct BuildInfoParsingTests {

    @Test("Strips surrounding quotes from version.txt values")
    func stripsQuotes() {
        let raw = """
        ===BRANCH===
        BRANCH="develop"
        ===BUILDTIME===
        BUILD_TIME="Fri Aug 4 12:34:56 2026"
        ===END===
        """
        let info = BuildInfo.parse(raw)
        #expect(info.branch == "develop")
        #expect(info.buildTime == "Fri Aug 4 12:34:56 2026")
    }

    @Test("Missing sections parse as nil")
    func missingSections() {
        let info = BuildInfo.parse("===IMAGE===\n===END===")
        #expect(info.imageName == nil)
        #expect(info.middleware == nil)
    }

    @Test("Strips syslog prefix from log lines")
    func stripsLogPrefix() {
        let raw = """
        ===VIPA===
        2026-08-04 10:00:00 viper_ipa widget version: 5.6.7
        ===END===
        """
        let info = BuildInfo.parse(raw)
        #expect(info.vipa == "5.6.7")
    }

    @Test("Report renders every row, using (not found) for gaps")
    func reportRendersRows() {
        let report = BuildInfoReport.format(BuildInfo(imageName: "IMG_1"))
        #expect(report.contains("Image Name"))
        #expect(report.contains("IMG_1"))
        #expect(report.contains("(not found)"))
        #expect(report.contains("Device Build Info"))
    }
}

// MARK: - Cancellation (item 3)

@Suite("Cancellation")
struct CancellationTests {

    @Test("Cancelling an install aborts before flashing")
    @MainActor func cancelInstallAbortsBeforeFlash() async throws {
        let session = makeSession()
        let scp = MockSCPService()
        scp.blockUntilCancelled = true
        let ssh = MockSSHService()
        let vm = InstallViewModel(session: session, scp: scp, ssh: ssh)

        vm.installBuild()
        // Wait until the SCP transfer is actually in progress.
        try await waitUntil { scp.transferCount == 1 }
        #expect(session.isRunning)
        #expect(session.activeAction == .install)

        // Pressing Install again while running cancels the in-flight task.
        vm.installBuild()
        try await waitUntilIdle(session)

        #expect(ssh.commands.isEmpty)                       // flash & reboot never ran
        #expect(session.progressLog.contains("Cancelling"))
        #expect(!session.isRunning)
        #expect(session.activeAction == nil)
    }

    @Test("Cancelling a download stops the transfer")
    @MainActor func cancelDownload() async throws {
        let session = makeSession()
        let scp = MockSCPService()
        scp.blockUntilCancelled = true
        let ssh = MockSSHService()
        let vm = InstallViewModel(session: session, scp: scp, ssh: ssh)

        vm.downloadBuild()
        try await waitUntil { scp.transferCount == 1 }
        #expect(session.activeAction == .download)

        vm.downloadBuild()   // toggle -> cancel
        try await waitUntilIdle(session)

        #expect(session.progressLog.contains("Cancelling"))
        #expect(!session.isRunning)
        #expect(session.activeAction == nil)
    }

    @Test("A second non-cancellable action is ignored while running")
    @MainActor func secondActionIgnoredWhileRunning() async throws {
        let session = makeSession()
        let scp = MockSCPService()
        scp.blockUntilCancelled = true
        let ssh = MockSSHService()
        let vm = InstallViewModel(session: session, scp: scp, ssh: ssh)

        vm.installBuild()
        try await waitUntil { scp.transferCount == 1 }

        // Reboot/flash should be no-ops while an install is running.
        vm.rebootOnly()
        vm.flashAppOnly()
        #expect(ssh.commands.isEmpty)

        vm.installBuild()          // cancel to let the test finish
        try await waitUntilIdle(session)
    }
}

// MARK: - Config Load & stderr isolation (item 4)

@Suite("Config Load")
struct ConfigLoadTests {

    @Test("Load populates config from stdout only, never stderr")
    @MainActor func loadIsolatesStderr() async throws {
        let session = makeSession()
        let ssh = MockSSHService()
        ssh.stdout = "info=true\nprogress=true\n"
        ssh.stderr = "Warning: Permanently added '[10.0.0.1]:10022' (RSA) to the list of known hosts.\n"
        let vm = ConfigEditorViewModel(session: session, ssh: ssh, defaults: makeTestDefaults())
        vm.configText = "OLD CONTENT"

        vm.loadConfigFromDevice()
        try await waitUntilIdle(session)

        #expect(vm.configText == "info=true\nprogress=true\n")
        #expect(!vm.configText.contains("Warning"))           // stderr kept out of config
        #expect(session.progressLog.contains("Warning"))      // ...but still logged
        #expect(session.progressLog.contains("Config loaded"))
    }

    @Test("A failed load leaves the existing config text unchanged")
    @MainActor func failedLoadKeepsText() async throws {
        let session = makeSession()
        let ssh = MockSSHService()
        ssh.exitStatus = 1
        let vm = ConfigEditorViewModel(session: session, ssh: ssh, defaults: makeTestDefaults())
        vm.configText = "KEEP ME"

        vm.loadConfigFromDevice()
        try await waitUntilIdle(session)

        #expect(vm.configText == "KEEP ME")
        #expect(session.progressLog.contains("Failed to read config"))
    }

    @Test("An empty config file is reported and clears the editor")
    @MainActor func emptyConfigReported() async throws {
        let session = makeSession()
        let ssh = MockSSHService()   // empty stdout, exit 0
        let vm = ConfigEditorViewModel(session: session, ssh: ssh, defaults: makeTestDefaults())
        vm.configText = "PREVIOUS"

        vm.loadConfigFromDevice()
        try await waitUntilIdle(session)

        #expect(vm.configText == "")
        #expect(session.progressLog.contains("No config on device"))
    }

    @Test("Load reads from the correct remote path")
    @MainActor func loadUsesCorrectPath() async throws {
        let session = makeSession()
        let ssh = MockSSHService()
        ssh.stdout = "x=1\n"
        let vm = ConfigEditorViewModel(session: session, ssh: ssh, defaults: makeTestDefaults())

        vm.loadConfigFromDevice()
        try await waitUntilIdle(session)

        let command = try #require(ssh.commands.first)
        #expect(command.contains("cat /opt/aamp.cfg"))
    }
}
