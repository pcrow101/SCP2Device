import Testing
import Foundation
@testable import SCP2Device

// MARK: - IP Validation

@Suite("IP Address Validation")
struct IPValidationTests {

    @Test("Valid IPv4 addresses are accepted")
    @MainActor func validIPs() {
        let session = DeviceSession(defaults: makeTestDefaults())
        #expect(session.isValidIP("192.168.1.1"))
        #expect(session.isValidIP("0.0.0.0"))
        #expect(session.isValidIP("255.255.255.255"))
        #expect(session.isValidIP("10.0.0.1"))
    }

    @Test("Invalid IPv4 addresses are rejected")
    @MainActor func invalidIPs() {
        let session = DeviceSession(defaults: makeTestDefaults())
        #expect(!session.isValidIP(""))
        #expect(!session.isValidIP("not.an.ip"))
        #expect(!session.isValidIP("192.168.1"))
        #expect(!session.isValidIP("192.168.1.1.1"))
        #expect(!session.isValidIP("256.1.1.1"))
        #expect(!session.isValidIP("192.168.1.-1"))
        #expect(!session.isValidIP("192.168.1.999"))
        #expect(!session.isValidIP("abc.def.ghi.jkl"))
    }
}

// MARK: - Input Validation

@Suite("Full Input Validation")
struct InputValidationTests {

    @Test("Empty build path fails validation")
    @MainActor func emptyBuildPath() {
        let session = DeviceSession(defaults: makeTestDefaults())
        session.buildPath = ""
        session.ipAddress = "192.168.1.1"
        session.progressLog = ""
        #expect(!session.validateInputs())
        #expect(session.progressLog.contains("No build file selected"))
    }

    @Test("Non-existent build file fails validation")
    @MainActor func missingBuildFile() {
        let session = DeviceSession(defaults: makeTestDefaults())
        session.buildPath = "/nonexistent/path/to/build.bin"
        session.ipAddress = "192.168.1.1"
        session.progressLog = ""
        #expect(!session.validateInputs())
        #expect(session.progressLog.contains("Build file does not exist"))
    }

    @Test("Empty IP address fails validation")
    @MainActor func emptyIP() {
        let session = DeviceSession(defaults: makeTestDefaults())
        session.buildPath = "/bin/ls" // guaranteed to exist
        session.ipAddress = ""
        session.progressLog = ""
        #expect(!session.validateInputs())
        #expect(session.progressLog.contains("IP address is empty"))
    }

    @Test("Invalid IP fails validation")
    @MainActor func invalidIP() {
        let session = DeviceSession(defaults: makeTestDefaults())
        session.buildPath = "/bin/ls"
        session.ipAddress = "999.999.999.999"
        session.progressLog = ""
        #expect(!session.validateInputs())
        #expect(session.progressLog.contains("not a valid IP address"))
    }

    @Test("Valid inputs pass validation")
    @MainActor func validInputs() {
        let session = DeviceSession(defaults: makeTestDefaults())
        session.buildPath = "/bin/ls" // exists on disk
        session.ipAddress = "192.168.1.1"
        session.destinationFolder = "/tmp"
        session.progressLog = ""
        #expect(session.validateInputs())
        #expect(session.progressLog.isEmpty)
    }
}

// MARK: - IP-only Validation

@Suite("IP and Destination Validation")
struct IPAndDestinationValidationTests {

    @Test("Empty IP fails")
    @MainActor func emptyIP() {
        let session = DeviceSession(defaults: makeTestDefaults())
        session.ipAddress = "  "
        session.progressLog = ""
        #expect(!session.validateIPAndDestination())
        #expect(session.progressLog.contains("IP address is empty"))
    }

    @Test("Empty destination folder fails")
    @MainActor func emptyDestination() {
        let session = DeviceSession(defaults: makeTestDefaults())
        session.ipAddress = "10.0.0.1"
        session.destinationFolder = "  "
        session.progressLog = ""
        #expect(!session.validateIPAndDestination())
        #expect(session.progressLog.contains("Destination folder is empty"))
    }

    @Test("Valid IP and destination passes")
    @MainActor func validIPAndDestination() {
        let session = DeviceSession(defaults: makeTestDefaults())
        session.ipAddress = "10.0.0.1"
        session.destinationFolder = "/tmp"
        session.progressLog = ""
        #expect(session.validateIPAndDestination())
    }
}

// MARK: - History Management

@Suite("History Management")
struct HistoryTests {

    @Test("IP is added to history")
    @MainActor func addIP() {
        let session = DeviceSession(defaults: makeTestDefaults())
        session.ipAddressHistory = []
        session.addIPToHistory("10.0.0.1")
        #expect(session.ipAddressHistory == ["10.0.0.1"])
    }

    @Test("Duplicate IP is moved to the front")
    @MainActor func duplicateIPMovedToFront() {
        let session = DeviceSession(defaults: makeTestDefaults())
        session.ipAddressHistory = ["10.0.0.2", "10.0.0.1"]
        session.addIPToHistory("10.0.0.1")
        #expect(session.ipAddressHistory.first == "10.0.0.1")
        #expect(session.ipAddressHistory.count == 2)
    }

    @Test("IP history is capped at 10")
    @MainActor func ipHistoryCapped() {
        let session = DeviceSession(defaults: makeTestDefaults())
        session.ipAddressHistory = (1...10).map { "10.0.0.\($0)" }
        session.addIPToHistory("10.0.0.99")
        #expect(session.ipAddressHistory.count == 10)
        #expect(session.ipAddressHistory.first == "10.0.0.99")
        #expect(!session.ipAddressHistory.contains("10.0.0.10"))
    }

    @Test("Build path is added to history")
    @MainActor func addBuildPath() {
        let session = DeviceSession(defaults: makeTestDefaults())
        session.buildPathHistory = []
        session.addBuildToHistory("/path/to/build.bin")
        #expect(session.buildPathHistory == ["/path/to/build.bin"])
    }

    @Test("Duplicate build path is moved to front")
    @MainActor func duplicateBuildMovedToFront() {
        let session = DeviceSession(defaults: makeTestDefaults())
        session.buildPathHistory = ["/second.bin", "/first.bin"]
        session.addBuildToHistory("/first.bin")
        #expect(session.buildPathHistory.first == "/first.bin")
        #expect(session.buildPathHistory.count == 2)
    }

    @Test("Build history is capped at 10")
    @MainActor func buildHistoryCapped() {
        let session = DeviceSession(defaults: makeTestDefaults())
        session.buildPathHistory = (1...10).map { "/build\($0).bin" }
        session.addBuildToHistory("/new.bin")
        #expect(session.buildPathHistory.count == 10)
        #expect(session.buildPathHistory.first == "/new.bin")
    }

    @Test("Empty build path is not added")
    @MainActor func emptyBuildPathNotAdded() {
        let session = DeviceSession(defaults: makeTestDefaults())
        session.buildPathHistory = []
        session.addBuildToHistory("")
        #expect(session.buildPathHistory.isEmpty)
    }
}

// MARK: - Log Management

@Suite("Progress Log")
struct LogTests {

    @Test("appendLog appends text")
    @MainActor func appendLog() {
        let session = DeviceSession(defaults: makeTestDefaults())
        session.progressLog = ""
        session.appendLog("Hello")
        session.appendLog(" World")
        #expect(session.progressLog == "Hello World")
    }

    @Test("clearLog clears text")
    @MainActor func clearLog() {
        let session = DeviceSession(defaults: makeTestDefaults())
        session.progressLog = "Some old output"
        session.clearLog()
        #expect(session.progressLog.isEmpty)
    }
}

// MARK: - Build Selection

@Suite("Build Selection")
struct BuildSelectionTests {

    @Test("Existing file is accepted")
    @MainActor func acceptsExistingFile() {
        let session = DeviceSession(defaults: makeTestDefaults())
        session.progressLog = ""
        let accepted = session.setBuildPath(from: URL(fileURLWithPath: "/bin/ls"))
        #expect(accepted)
        #expect(session.buildPath == "/bin/ls")
    }

    @Test("Directory is rejected")
    @MainActor func rejectsDirectory() {
        let session = DeviceSession(defaults: makeTestDefaults())
        session.buildPath = ""
        session.progressLog = ""
        let accepted = session.setBuildPath(from: URL(fileURLWithPath: "/tmp"))
        #expect(!accepted)
        #expect(session.buildPath.isEmpty)
        #expect(session.progressLog.contains("Drop ignored"))
    }

    @Test("Missing file is rejected")
    @MainActor func rejectsMissingFile() {
        let session = DeviceSession(defaults: makeTestDefaults())
        session.buildPath = ""
        session.progressLog = ""
        let accepted = session.setBuildPath(from: URL(fileURLWithPath: "/no/such/file.bin"))
        #expect(!accepted)
        #expect(session.buildPath.isEmpty)
    }
}

// MARK: - Default Values

@Suite("Default Values")
struct DefaultValueTests {

    @Test("Default destination folder is /tmp")
    @MainActor func defaultDestination() {
        // A fresh, isolated defaults suite gives us true first-launch values.
        let session = DeviceSession(defaults: makeTestDefaults())
        #expect(session.destinationFolder == "/tmp")
    }

    @Test("First launch has empty history and no build selected")
    @MainActor func firstLaunchIsEmpty() {
        let session = DeviceSession(defaults: makeTestDefaults())
        #expect(session.buildPath.isEmpty)
        #expect(session.ipAddress.isEmpty)
        #expect(session.buildPathHistory.isEmpty)
        #expect(session.ipAddressHistory.isEmpty)
    }

    @Test("Session does not write to the real application defaults")
    @MainActor func doesNotTouchStandardDefaults() {
        let marker = "/marker-\(UUID().uuidString).bin"
        let session = DeviceSession(defaults: makeTestDefaults())
        session.addBuildToHistory(marker)

        let standardHistory = UserDefaults.standard.stringArray(forKey: "buildPathHistory") ?? []
        #expect(!standardHistory.contains(marker))
    }
}
