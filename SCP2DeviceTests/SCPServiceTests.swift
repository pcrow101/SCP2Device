import Testing
import Foundation
@testable import SCP2Device

// MARK: - SCP Progress Parsing

@Suite("SCP Progress Parsing")
struct SCPProgressParsingTests {

    @Test("Parses standard SCP progress line")
    func standardProgress() {
        let line = "bigtest.bin                                  10MB  42%    5.00MB/s   0:00:05"
        let result = SCPService.parseProgress(from: line)
        #expect(result == 42)
    }

    @Test("Parses 0% progress")
    func zeroPercent() {
        let line = "build.bin                                    0KB   0%    0.00B/s    0:00:00"
        let result = SCPService.parseProgress(from: line)
        #expect(result == 0)
    }

    @Test("Parses 100% progress")
    func hundredPercent() {
        let line = "build.bin                                    50MB 100%   10.0MB/s   0:00:05"
        let result = SCPService.parseProgress(from: line)
        #expect(result == 100)
    }

    @Test("Returns nil for non-progress lines")
    func nonProgressLine() {
        let line = "Warning: Permanently added '192.168.1.1' (ECDSA) to the list of known hosts."
        let result = SCPService.parseProgress(from: line)
        #expect(result == nil)
    }

    @Test("Returns nil for empty string")
    func emptyString() {
        #expect(SCPService.parseProgress(from: "") == nil)
    }

    @Test("Returns nil for percentage without time field")
    func percentWithoutTime() {
        // No colon → no time field → not a real progress line
        let line = "Loading 50%"
        let result = SCPService.parseProgress(from: line)
        #expect(result == nil)
    }

    @Test("Parses ETA-style time field")
    func etaTimeField() {
        let line = "firmware.bin                                 25MB  75%    8.5MB/s   0:01:23"
        let result = SCPService.parseProgress(from: line)
        #expect(result == 75)
    }

    @Test("Handles single-digit percentage")
    func singleDigitPercent() {
        let line = "file.bin  1KB   5%  100KB/s  0:00:10"
        let result = SCPService.parseProgress(from: line)
        #expect(result == 5)
    }
}

// MARK: - SCP Progress False Positives (item 2)

@Suite("SCP Progress False Positives")
struct SCPProgressFalsePositiveTests {

    @Test("IP:port lines are not read as progress")
    func ipPortIsNotProgress() {
        // Colon present, but no percentage -> not progress.
        #expect(SCPService.parseProgress(from: "Connecting to 10.0.0.5:10022") == nil)
    }

    @Test("scp error lines are not read as progress")
    func scpErrorIsNotProgress() {
        #expect(SCPService.parseProgress(from: "scp: /tmp/build.bin: Operation not permitted") == nil)
    }

    @Test("ssh debug lines are not read as progress")
    func sshDebugIsNotProgress() {
        #expect(SCPService.parseProgress(from: "debug1: reading configuration data") == nil)
    }

    @Test("A plain IP address is not read as progress")
    func plainIPIsNotProgress() {
        // No colon and no percentage.
        #expect(SCPService.parseProgress(from: "192.168.1.100") == nil)
    }

    @Test("Out-of-range percentages are rejected even with a colon")
    func outOfRangePercentRejected() {
        #expect(SCPService.parseProgress(from: "processing 255%: nearly there") == nil)
        #expect(SCPService.parseProgress(from: "value 999%  0:00:01") == nil)
    }

    @Test("A filename containing digits does not confuse the parser")
    func filenameDigitsDoNotConfuse() {
        // "1percent.bin" has leading digits but the real percentage is 3%.
        let line = "1percent.bin   10MB   3%   1.0MB/s   0:00:01"
        #expect(SCPService.parseProgress(from: line) == 3)
    }
}

// MARK: - SSH Command Construction

@Suite("SSH Command Construction")
struct SSHCommandTests {

    @Test("SSH command string contains expected arguments")
    @MainActor func sshCommandArguments() async {
        let service = SSHService()
        var loggedCommand = ""

        // ssh will fail to connect (no server on port 10022 locally) but
        // the command string is logged via onOutput *before* the process runs.
        do {
            _ = try await service.execute(
                deviceIP: "127.0.0.1",
                command: "echo test",
                onOutput: { text in loggedCommand += text }
            )
        } catch {
            // expected — no SSH server on 10022
        }

        #expect(loggedCommand.contains("-p 10022"))
        #expect(loggedCommand.contains("-o StrictHostKeyChecking=no"))
        #expect(loggedCommand.contains("-o UserKnownHostsFile=/dev/null"))
        #expect(loggedCommand.contains("root@127.0.0.1"))
        #expect(loggedCommand.contains("echo test"))
    }
}
