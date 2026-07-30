import Foundation

/// Wraps the system `ssh` command executed via `Foundation.Process`.
/// Streams stdout / stderr output through an async callback.
struct SSHService: Sendable {

    /// Executes a remote command over SSH.
    /// Always uses: port 10022, StrictHostKeyChecking=no,
    /// UserKnownHostsFile=/dev/null, and root as the remote user.
    @discardableResult
    func execute(
        deviceIP: String,
        command: String,
        onOutput: @MainActor @escaping @Sendable (String) -> Void,
        onProcessStarted: @MainActor @escaping @Sendable (Process) -> Void = { _ in }
    ) async throws -> Int32 {

        let arguments: [String] = [
            "-p", "10022",
            "-o", "ConnectTimeout=5",
            "-o", "StrictHostKeyChecking=no",
            "-o", "UserKnownHostsFile=/dev/null",
            "root@\(deviceIP)",
            command
        ]

        let commandString = "ssh " + arguments.joined(separator: " ")
        onOutput("▶ \(commandString)\n")

        return try await runProcess(
            launchPath: "/usr/bin/ssh",
            arguments: arguments,
            onOutput: onOutput,
            onProcessStarted: onProcessStarted
        )
    }

    // MARK: - Private

    private func runProcess(
        launchPath: String,
        arguments: [String],
        onOutput: @MainActor @escaping @Sendable (String) -> Void,
        onProcessStarted: @MainActor @escaping @Sendable (Process) -> Void
    ) async throws -> Int32 {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: launchPath)
            process.arguments = arguments

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                Task { @MainActor in onOutput(text) }
            }

            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                Task { @MainActor in onOutput(text) }
            }

            process.terminationHandler = { proc in
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                continuation.resume(returning: proc.terminationStatus)
            }

            do {
                try process.run()
                Task { @MainActor in onProcessStarted(process) }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
