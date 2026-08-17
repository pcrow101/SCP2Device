import Testing
import Foundation
@testable import SCP2Device

// MARK: - Log line colour classification

@Suite("Log Line Styling")
struct LogLineStyleTests {

    // Glyph-prefixed app lines

    @Test("Success glyph is green")
    func successGlyph() {
        #expect(LogLineStyle.classify("✔ Build transferred successfully.") == .success)
    }

    @Test("Failure glyph is red")
    func failureGlyph() {
        #expect(LogLineStyle.classify("✖ Failed to fetch build info (exit 255).") == .failure)
    }

    @Test("Warning glyph is orange")
    func warningGlyph() {
        #expect(LogLineStyle.classify("⚠ Cancelling…") == .warning)
    }

    @Test("Section header is styled distinctly")
    func sectionHeader() {
        #expect(LogLineStyle.classify("━━━ Fetching build info from device ━━━") == .sectionHeader)
    }

    @Test("Command echo is styled distinctly")
    func commandEcho() {
        #expect(LogLineStyle.classify("▶ ssh -p 10022 root@10.0.0.1 cat /version.txt") == .command)
    }

    @Test("Info arrow is styled distinctly")
    func infoArrow() {
        #expect(LogLineStyle.classify("→ Non-Llama device — using destination as-is.") == .info)
    }

    @Test("Build-info table lines are styled distinctly")
    func reportLines() {
        #expect(LogLineStyle.classify("┌─ Device Build Info ────") == .report)
        #expect(LogLineStyle.classify("│ Branch : develop") == .report)
        #expect(LogLineStyle.classify("└────────────") == .report)
    }

    // Raw tool output (the reported bug) — no glyph, must still be red

    @Test("SSH connection timeout is treated as a failure")
    func sshTimeoutIsFailure() {
        let line = "ssh: connect to host 192.168.1.188 port 10022: Operation timed out"
        #expect(LogLineStyle.classify(line) == .failure)
    }

    @Test("scp error prefix is treated as a failure")
    func scpErrorIsFailure() {
        #expect(LogLineStyle.classify("scp: /tmp/build.bin: No such file or directory") == .failure)
    }

    @Test("Connection refused is a failure")
    func connectionRefused() {
        #expect(LogLineStyle.classify("ssh: connect to host 10.0.0.1 port 10022: Connection refused") == .failure)
    }

    @Test("No route to host is a failure")
    func noRouteToHost() {
        #expect(LogLineStyle.classify("connect: No route to host") == .failure)
    }

    @Test("Permission denied is a failure")
    func permissionDenied() {
        #expect(LogLineStyle.classify("root@10.0.0.1: Permission denied (publickey,password).") == .failure)
    }

    @Test("Lost connection during transfer is a failure")
    func lostConnection() {
        #expect(LogLineStyle.classify("lost connection") == .failure)
    }

    // Warnings & plain

    @Test("Post-quantum warning text is a warning")
    func postQuantumWarning() {
        let line = "** WARNING: connection is not using a post-quantum key exchange algorithm."
        #expect(LogLineStyle.classify(line) == .warning)
    }

    @Test("Ordinary output stays plain")
    func ordinaryPlain() {
        #expect(LogLineStyle.classify("info=true") == .plain)
        #expect(LogLineStyle.classify("MIDDLEWARE_VERSION=1.2.3") == .plain)
    }

    @Test("Empty line is plain")
    func emptyLine() {
        #expect(LogLineStyle.classify("") == .plain)
    }

    @Test("Failure detection is case-insensitive")
    func caseInsensitive() {
        #expect(LogLineStyle.classify("Connection TIMED OUT") == .failure)
    }
}
