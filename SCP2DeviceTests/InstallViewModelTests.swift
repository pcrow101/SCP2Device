import Testing
import Foundation
@testable import SCP2Device

// MARK: - IP Validation

@Suite("IP Address Validation")
struct IPValidationTests {

    @Test("Valid IPv4 addresses are accepted")
    @MainActor func validIPs() {
        let vm = InstallViewModel()
        #expect(vm.isValidIP("192.168.1.1"))
        #expect(vm.isValidIP("0.0.0.0"))
        #expect(vm.isValidIP("255.255.255.255"))
        #expect(vm.isValidIP("10.0.0.1"))
    }

    @Test("Invalid IPv4 addresses are rejected")
    @MainActor func invalidIPs() {
        let vm = InstallViewModel()
        #expect(!vm.isValidIP(""))
        #expect(!vm.isValidIP("not.an.ip"))
        #expect(!vm.isValidIP("192.168.1"))
        #expect(!vm.isValidIP("192.168.1.1.1"))
        #expect(!vm.isValidIP("256.1.1.1"))
        #expect(!vm.isValidIP("192.168.1.-1"))
        #expect(!vm.isValidIP("192.168.1.999"))
        #expect(!vm.isValidIP("abc.def.ghi.jkl"))
    }
}

// MARK: - Input Validation

@Suite("Full Input Validation")
struct InputValidationTests {

    @Test("Empty build path fails validation")
    @MainActor func emptyBuildPath() {
        let vm = InstallViewModel()
        vm.buildPath = ""
        vm.ipAddress = "192.168.1.1"
        vm.progressLog = ""
        let result = vm.validateInputs()
        #expect(!result)
        #expect(vm.progressLog.contains("No build file selected"))
    }

    @Test("Non-existent build file fails validation")
    @MainActor func missingBuildFile() {
        let vm = InstallViewModel()
        vm.buildPath = "/nonexistent/path/to/build.bin"
        vm.ipAddress = "192.168.1.1"
        vm.progressLog = ""
        let result = vm.validateInputs()
        #expect(!result)
        #expect(vm.progressLog.contains("Build file does not exist"))
    }

    @Test("Empty IP address fails validation")
    @MainActor func emptyIP() {
        let vm = InstallViewModel()
        vm.buildPath = "/bin/ls" // guaranteed to exist
        vm.ipAddress = ""
        vm.progressLog = ""
        let result = vm.validateInputs()
        #expect(!result)
        #expect(vm.progressLog.contains("IP address is empty"))
    }

    @Test("Invalid IP fails validation")
    @MainActor func invalidIP() {
        let vm = InstallViewModel()
        vm.buildPath = "/bin/ls"
        vm.ipAddress = "999.999.999.999"
        vm.progressLog = ""
        let result = vm.validateInputs()
        #expect(!result)
        #expect(vm.progressLog.contains("not a valid IP address"))
    }

    @Test("Valid inputs pass validation")
    @MainActor func validInputs() {
        let vm = InstallViewModel()
        vm.buildPath = "/bin/ls" // exists on disk
        vm.ipAddress = "192.168.1.1"
        vm.destinationFolder = "/tmp"
        vm.progressLog = ""
        let result = vm.validateInputs()
        #expect(result)
        #expect(vm.progressLog.isEmpty)
    }
}

// MARK: - IP-only Validation

@Suite("IP and Destination Validation")
struct IPAndDestinationValidationTests {

    @Test("Empty IP fails")
    @MainActor func emptyIP() {
        let vm = InstallViewModel()
        vm.ipAddress = "  "
        vm.progressLog = ""
        #expect(!vm.validateIPAndDestination())
        #expect(vm.progressLog.contains("IP address is empty"))
    }

    @Test("Empty destination folder fails")
    @MainActor func emptyDestination() {
        let vm = InstallViewModel()
        vm.ipAddress = "10.0.0.1"
        vm.destinationFolder = "  "
        vm.progressLog = ""
        #expect(!vm.validateIPAndDestination())
        #expect(vm.progressLog.contains("Destination folder is empty"))
    }

    @Test("Valid IP and destination passes")
    @MainActor func validIPAndDestination() {
        let vm = InstallViewModel()
        vm.ipAddress = "10.0.0.1"
        vm.destinationFolder = "/tmp"
        vm.progressLog = ""
        #expect(vm.validateIPAndDestination())
    }
}

// MARK: - History Management

@Suite("History Management")
struct HistoryTests {

    @Test("IP is added to history")
    @MainActor func addIP() {
        let vm = InstallViewModel()
        vm.ipAddressHistory = []
        vm.addIPToHistory("10.0.0.1")
        #expect(vm.ipAddressHistory == ["10.0.0.1"])
    }

    @Test("Duplicate IP is moved to the front")
    @MainActor func duplicateIPMovedToFront() {
        let vm = InstallViewModel()
        vm.ipAddressHistory = ["10.0.0.2", "10.0.0.1"]
        vm.addIPToHistory("10.0.0.1")
        #expect(vm.ipAddressHistory.first == "10.0.0.1")
        #expect(vm.ipAddressHistory.count == 2)
    }

    @Test("IP history is capped at 10")
    @MainActor func ipHistoryCapped() {
        let vm = InstallViewModel()
        vm.ipAddressHistory = (1...10).map { "10.0.0.\($0)" }
        vm.addIPToHistory("10.0.0.99")
        #expect(vm.ipAddressHistory.count == 10)
        #expect(vm.ipAddressHistory.first == "10.0.0.99")
        #expect(!vm.ipAddressHistory.contains("10.0.0.10"))
    }

    @Test("Build path is added to history")
    @MainActor func addBuildPath() {
        let vm = InstallViewModel()
        vm.buildPathHistory = []
        vm.addBuildToHistory("/path/to/build.bin")
        #expect(vm.buildPathHistory == ["/path/to/build.bin"])
    }

    @Test("Duplicate build path is moved to front")
    @MainActor func duplicateBuildMovedToFront() {
        let vm = InstallViewModel()
        vm.buildPathHistory = ["/second.bin", "/first.bin"]
        vm.addBuildToHistory("/first.bin")
        #expect(vm.buildPathHistory.first == "/first.bin")
        #expect(vm.buildPathHistory.count == 2)
    }

    @Test("Build history is capped at 10")
    @MainActor func buildHistoryCapped() {
        let vm = InstallViewModel()
        vm.buildPathHistory = (1...10).map { "/build\($0).bin" }
        vm.addBuildToHistory("/new.bin")
        #expect(vm.buildPathHistory.count == 10)
        #expect(vm.buildPathHistory.first == "/new.bin")
    }

    @Test("Empty build path is not added")
    @MainActor func emptyBuildPathNotAdded() {
        let vm = InstallViewModel()
        vm.buildPathHistory = []
        vm.addBuildToHistory("")
        #expect(vm.buildPathHistory.isEmpty)
    }
}

// MARK: - Log Management

@Suite("Progress Log")
struct LogTests {

    @Test("appendLog appends text")
    @MainActor func appendLog() {
        let vm = InstallViewModel()
        vm.progressLog = ""
        vm.appendLog("Hello")
        vm.appendLog(" World")
        #expect(vm.progressLog == "Hello World")
    }

    @Test("clearLog clears text")
    @MainActor func clearLog() {
        let vm = InstallViewModel()
        vm.progressLog = "Some old output"
        vm.clearLog()
        #expect(vm.progressLog.isEmpty)
    }
}

// MARK: - Default Values

@Suite("Default Values")
struct DefaultValueTests {

    @Test("Default destination folder is /tmp")
    @MainActor func defaultDestination() {
        // Remove stored value so we get the true default
        UserDefaults.standard.removeObject(forKey: "destinationFolder")
        let vm = InstallViewModel()
        #expect(vm.destinationFolder == "/tmp")
    }
}
