import Foundation

/// Wraps `scp` run inside `script -q /dev/null` so scp sees a TTY and emits
/// progress lines. Everything arrives on one stdout pipe, split on \r / \n.
struct SCPService: Sendable {

    @discardableResult
    func transfer(
        buildPath: String,
        deviceIP: String,
        destinationFolder: String,
        onOutput: @MainActor @escaping @Sendable (String) -> Void,
        onProgress: @MainActor @escaping @Sendable (Double?) -> Void,
        onProcessStarted: @MainActor @escaping @Sendable (Process) -> Void = { _ in }
    ) async throws -> Int32 {

        // Build the scp argument list (will be passed to script)
        let scpArgs: [String] = [
            "/usr/bin/scp",
            "-P", "10022",
            "-O",
            "-o", "ConnectTimeout=5",
            "-o", "StrictHostKeyChecking=no",
            "-o", "UserKnownHostsFile=/dev/null",
            buildPath,
            "root@\(deviceIP):\(destinationFolder)"
        ]

        // Log the scp command (skip the leading "script -q /dev/null" wrapper)
        let commandString = scpArgs.joined(separator: " ")
        onOutput("▶ \(commandString)\n")

        // Wrap in `script -q /dev/null` so scp's stderr is a PTY → progress enabled.
        // script merges everything onto its own stdout which we read via a normal Pipe.
        return try await runProcess(
            launchPath: "/usr/bin/script",
            arguments: ["-q", "/dev/null"] + scpArgs,
            onOutput: onOutput,
            onProgress: onProgress,
            onProcessStarted: onProcessStarted
        )
    }

    // MARK: - Private

    private func runProcess(
        launchPath: String,
        arguments: [String],
        onOutput: @MainActor @escaping @Sendable (String) -> Void,
        onProgress: @MainActor @escaping @Sendable (Double?) -> Void,
        onProcessStarted: @MainActor @escaping @Sendable (Process) -> Void
    ) async throws -> Int32 {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: launchPath)
            process.arguments = arguments

            // Single pipe for everything — script merges stdout+stderr of scp
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError  = pipe

            // Accumulate bytes and split on \r (progress) and \n (regular lines)
            let bufferQueue = DispatchQueue(label: "scp.buffer")
            var buffer = Data()

            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                bufferQueue.sync { buffer.append(data) }

                // Process all complete lines (terminated by \r or \n)
                bufferQueue.sync {
                    while let idx = buffer.firstIndex(where: { $0 == 0x0D || $0 == 0x0A }) {
                        let lineData = buffer[buffer.startIndex..<idx]
                        // Skip the terminator (and an extra \n if \r\n pair)
                        var next = buffer.index(after: idx)
                        if buffer[idx] == 0x0D,
                           next < buffer.endIndex,
                           buffer[next] == 0x0A {
                            next = buffer.index(after: next)
                        }
                        buffer = buffer[next...]

                        guard let line = String(data: lineData, encoding: .utf8)?
                            .trimmingCharacters(in: .whitespaces),
                              !line.isEmpty else { continue }

                        if let pct = Self.parseProgress(from: line) {
                            Task { @MainActor in onProgress(pct) }
                        } else {
                            Task { @MainActor in onOutput(line + "\n") }
                        }
                    }
                }
            }

            process.terminationHandler = { proc in
                pipe.fileHandleForReading.readabilityHandler = nil
                // Flush any unterminated remainder
                bufferQueue.sync {
                    if let remaining = String(data: buffer, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines),
                       !remaining.isEmpty {
                        Task { @MainActor in onOutput(remaining + "\n") }
                    }
                }
                Task { @MainActor in onProgress(nil) }
                continuation.resume(returning: proc.terminationStatus)
            }

            do {
                try process.run()
                Task { @MainActor in onProcessStarted(process) }
            } catch {
                pipe.fileHandleForReading.readabilityHandler = nil
                continuation.resume(throwing: error)
            }
        }
    }

    /// Parses an SCP progress line like "bigtest.bin  10 MB  42%  5.00MB/s  0:00:05"
    static func parseProgress(from text: String) -> Double? {
        // Must contain a time-remaining field (0:00:00) to be a genuine progress line
        // and a percentage value
        guard text.contains(":") else { return nil }
        let pattern = #"\b(\d{1,3})%"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text,
                                           range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text),
              let pct = Double(text[range]),
              (0...100).contains(pct)
        else { return nil }
        return pct
    }
}
