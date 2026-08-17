import Foundation

/// Abstraction over the SCP transfer so the view models can be tested with
/// a mock instead of spawning a real `scp` process.
protocol SCPServicing: Sendable {
    @discardableResult
    func transfer(
        buildPath: String,
        deviceIP: String,
        destinationFolder: String,
        onOutput: @MainActor @escaping @Sendable (String) -> Void,
        onProgress: @MainActor @escaping @Sendable (Double?) -> Void,
        onProcessStarted: @MainActor @escaping @Sendable (Process) -> Void
    ) async throws -> Int32
}

/// Abstraction over remote SSH command execution.
protocol SSHServicing: Sendable {
    @discardableResult
    func execute(
        deviceIP: String,
        command: String,
        stdin: String?,
        onOutput: @MainActor @escaping @Sendable (String) -> Void,
        onError: (@MainActor @Sendable (String) -> Void)?,
        onProcessStarted: @MainActor @escaping @Sendable (Process) -> Void
    ) async throws -> Int32
}

// MARK: - Convenience overloads
//
// Protocol requirements can't declare default arguments, so the common
// call shapes are provided here instead. Keeping them in an extension (rather
// than as defaults on the concrete types) avoids overload ambiguity.

extension SSHServicing {

    /// Run a command, streaming stdout/stderr to a single sink.
    @discardableResult
    func execute(
        deviceIP: String,
        command: String,
        onOutput: @MainActor @escaping @Sendable (String) -> Void,
        onProcessStarted: @MainActor @escaping @Sendable (Process) -> Void = { _ in }
    ) async throws -> Int32 {
        try await execute(deviceIP: deviceIP,
                          command: command,
                          stdin: nil,
                          onOutput: onOutput,
                          onError: nil,
                          onProcessStarted: onProcessStarted)
    }

    /// Run a command with stdout and stderr routed to separate sinks.
    @discardableResult
    func execute(
        deviceIP: String,
        command: String,
        onOutput: @MainActor @escaping @Sendable (String) -> Void,
        onError: @MainActor @escaping @Sendable (String) -> Void,
        onProcessStarted: @MainActor @escaping @Sendable (Process) -> Void = { _ in }
    ) async throws -> Int32 {
        try await execute(deviceIP: deviceIP,
                          command: command,
                          stdin: nil,
                          onOutput: onOutput,
                          onError: onError,
                          onProcessStarted: onProcessStarted)
    }

    /// Run a command, feeding `stdin` to the remote process.
    @discardableResult
    func execute(
        deviceIP: String,
        command: String,
        stdin: String,
        onOutput: @MainActor @escaping @Sendable (String) -> Void,
        onProcessStarted: @MainActor @escaping @Sendable (Process) -> Void = { _ in }
    ) async throws -> Int32 {
        try await execute(deviceIP: deviceIP,
                          command: command,
                          stdin: stdin,
                          onOutput: onOutput,
                          onError: nil,
                          onProcessStarted: onProcessStarted)
    }
}
