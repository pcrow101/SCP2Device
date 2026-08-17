import Foundation
@testable import SCP2Device

/// Creates a throwaway `UserDefaults` suite so tests never read or write the
/// real application defaults.
///
/// Without this, tests that exercise history/persistence (e.g. "build history
/// is capped at 10") would leave `/build1.bin`, `/new.bin`, `/bin/ls` etc. in
/// the app's stored history and they'd appear in the UI on next launch.
func makeTestDefaults(function: String = #function) -> UserDefaults {
    let suiteName = "SCP2DeviceTests.\(function).\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

@MainActor
func makeTestSession(ip: String = "10.0.0.1",
                     build: String = "/bin/ls",
                     destination: String = "/tmp",
                     function: String = #function) -> DeviceSession {
    let session = DeviceSession(defaults: makeTestDefaults(function: function))
    session.ipAddress = ip
    session.buildPath = build
    session.destinationFolder = destination
    session.progressLog = ""
    return session
}
