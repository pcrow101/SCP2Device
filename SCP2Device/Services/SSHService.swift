import Foundation

/// Wraps the system `ssh` command executed via `Foundation.Process`.
/// Streams stdout / stderr output through an async callback.
struct SSHService: SSHServicing {

    /// Explicitly nonisolated so it can be used as a default argument value
    /// (default arguments are evaluated in a nonisolated context, and the
    /// project builds with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`).
    nonisolated init() {}

    /// Executes a remote command over SSH.
    /// Always uses: port 10022, ConnectTimeout=5, StrictHostKeyChecking=no,
    /// UserKnownHostsFile=/dev/null, LogLevel=ERROR, and root as the remote user.
    /// If `stdin` is provided, it is written to the remote command's standard input.
    /// `onError` (if given) receives stderr; otherwise stderr is sent to `onOutput`.
    @discardableResult
    func execute(
        deviceIP: String,
        command: String,
        stdin: String?,
        onOutput: @MainActor @escaping @Sendable (String) -> Void,
        onError: (@MainActor @Sendable (String) -> Void)?,
        onProcessStarted: @MainActor @escaping @Sendable (Process) -> Void
    ) async throws -> Int32 {

        let arguments: [String] = [
            "-p", "10022",
            "-o", "ConnectTimeout=5",
            "-o", "StrictHostKeyChecking=no",
            "-o", "UserKnownHostsFile=/dev/null",
            "-o", "LogLevel=ERROR",
            "root@\(deviceIP)",
            command
        ]

        let commandString = "ssh " + arguments.joined(separator: " ")
        onOutput("▶ \(commandString)\n")

        return try await runProcess(
            launchPath: "/usr/bin/ssh",
            arguments: arguments,
            stdin: stdin,
            onOutput: onOutput,
            onError: onError,
            onProcessStarted: onProcessStarted
        )
    }

    // MARK: - Private

    private func runProcess(
        launchPath: String,
        arguments: [String],
        stdin: String?,
        onOutput: @MainActor @escaping @Sendable (String) -> Void,
        onError: (@MainActor @Sendable (String) -> Void)?,
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

            // Provide stdin only when needed so normal SSH calls are unaffected.
            let stdinPipe: Pipe? = stdin != nil ? Pipe() : nil
            if let stdinPipe { process.standardInput = stdinPipe }

            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                Task { @MainActor in onOutput(text) }
            }

            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                // Route stderr to onError when provided, otherwise fall back to onOutput.
                Task { @MainActor in
                    if let onError { onError(text) } else { onOutput(text) }
                }
            }

            process.terminationHandler = { proc in
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                continuation.resume(returning: proc.terminationStatus)
            }

            do {
                try process.run()
                Task { @MainActor in onProcessStarted(process) }

                // Feed stdin (e.g. the config file contents) then close it.
                if let stdinPipe, let stdin {
                    let handle = stdinPipe.fileHandleForWriting
                    handle.write(Data(stdin.utf8))
                    try? handle.close()
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
