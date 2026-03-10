//
//  ProcessStreamClient.swift
//  SidePiece
//
//  Dependency client for spawning and managing long-lived subprocesses with piped stdio.
//

import Dependencies
import DependenciesMacros
import Foundation

// MARK: - Types

public struct ProcessConfiguration: Sendable, Equatable {
    public let executablePath: String
    public let arguments: [String]
    public let environment: [String: String]?
    public let workingDirectory: URL?

    public init(
        executablePath: String,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        workingDirectory: URL? = nil
    ) {
        self.executablePath = executablePath
        self.arguments = arguments
        self.environment = environment
        self.workingDirectory = workingDirectory
    }
}

public struct ProcessHandle: Sendable {
    public let stdout: AsyncThrowingStream<String, Error>
    public let stderr: AsyncThrowingStream<String, Error>
    public let writeLine: @Sendable (String) async throws -> Void
    public let closeStdin: @Sendable () async -> Void
    public let terminate: @Sendable () async -> Void
    public let isRunning: @Sendable () async -> Bool

    public init(
        stdout: AsyncThrowingStream<String, Error>,
        stderr: AsyncThrowingStream<String, Error>,
        writeLine: @Sendable @escaping (String) async throws -> Void,
        closeStdin: @Sendable @escaping () async -> Void,
        terminate: @Sendable @escaping () async -> Void,
        isRunning: @Sendable @escaping () async -> Bool
    ) {
        self.stdout = stdout
        self.stderr = stderr
        self.writeLine = writeLine
        self.closeStdin = closeStdin
        self.terminate = terminate
        self.isRunning = isRunning
    }
}

public enum ProcessStreamError: LocalizedError, Equatable, Sendable {
    case executableNotFound(path: String)
    case spawnFailed(message: String)
    case notRunning
    case stdinWriteFailed(message: String)
    case unexpectedTermination(exitCode: Int32, stderr: String?)

    public var errorDescription: String? {
        switch self {
        case .executableNotFound(let path):
            "Executable not found at path: \(path)"
        case .spawnFailed(let message):
            "Failed to spawn process: \(message)"
        case .notRunning:
            "Process is not running"
        case .stdinWriteFailed(let message):
            "Failed to write to stdin: \(message)"
        case .unexpectedTermination(let exitCode, let stderr):
            if let stderr, !stderr.isEmpty {
                "Process terminated with exit code \(exitCode):\n\(stderr)"
            } else {
                "Process terminated unexpectedly with exit code \(exitCode)"
            }
        }
    }
}

// MARK: - Dependency Client

@DependencyClient
public struct ProcessStreamClient: Sendable {
    public var spawn: @Sendable (_ configuration: ProcessConfiguration) async throws -> ProcessHandle
}

extension ProcessStreamClient: DependencyKey {
    public static let liveValue = ProcessStreamClient(
        spawn: { configuration in
            let actor = ProcessActor()
            return try await actor.spawn(configuration: configuration)
        }
    )
}

extension DependencyValues {
    public var processStreamClient: ProcessStreamClient {
        get { self[ProcessStreamClient.self] }
        set { self[ProcessStreamClient.self] = newValue }
    }
}

// MARK: - Process Actor

private actor ProcessActor {
    private var process: Process?
    private var stdinPipe: Pipe?

    // Extra PATH directories that may not be in a GUI app's minimal PATH
    private static let extraPathDirs: [String] = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appendingPathComponent(".local/bin").path,
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            home.appendingPathComponent(".cargo/bin").path,
        ]
    }()

    // Environment variables that should be stripped from child processes
    // to avoid issues like nested-session detection.
    private static let strippedEnvKeys: Set<String> = [
        "CLAUDECODE",
    ]

    private static func enrichedEnvironment(custom: [String: String]?) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        if let custom { for (k, v) in custom { env[k] = v } }

        // Remove environment variables that interfere with subprocess operation
        for key in strippedEnvKeys {
            env.removeValue(forKey: key)
        }

        // Enrich PATH so /usr/bin/env and child processes can find CLI tools
        let currentPath = env["PATH"] ?? "/usr/bin:/bin"
        var seen = Set<String>()
        var merged: [String] = []
        for dir in currentPath.split(separator: ":").map(String.init) + extraPathDirs {
            if seen.insert(dir).inserted {
                merged.append(dir)
            }
        }
        env["PATH"] = merged.joined(separator: ":")

        return env
    }

    func spawn(configuration: ProcessConfiguration) throws(ProcessStreamError) -> ProcessHandle {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let stdinPipe = Pipe()

        // No FileManager pre-checks — they fail under app sandbox.
        // For absolute paths, set executableURL directly.
        // For relative names (e.g. "claude"), use /usr/bin/env to resolve
        // via the enriched PATH (same pattern as Grep.swift).
        if configuration.executablePath.hasPrefix("/") {
            process.executableURL = URL(fileURLWithPath: configuration.executablePath)
            process.arguments = configuration.arguments
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [configuration.executablePath] + configuration.arguments
        }

        // Always set an enriched environment so executables and their
        // child processes can be found outside the app's minimal PATH
        process.environment = Self.enrichedEnvironment(custom: configuration.environment)

        if let wd = configuration.workingDirectory {
            process.currentDirectoryURL = wd
        }

        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = stdinPipe

        do {
            try process.run()
        } catch {
            throw .spawnFailed(message: error.localizedDescription)
        }
        print("[ProcessStream] PID \(process.processIdentifier) launched: \(configuration.executablePath)")

        self.process = process
        self.stdinPipe = stdinPipe

        // Accumulate stderr lines for inclusion in error messages
        let stderrAccumulator = StderrAccumulator()

        // Use readabilityHandler instead of bytes.lines — the async
        // iterator can silently stop reading when the subprocess pauses
        // output (e.g. waiting for an API response). readabilityHandler
        // reliably fires on every data chunk and on EOF (empty data).

        let stderr = Self.lineStream(
            from: stderrPipe.fileHandleForReading,
            accumulator: stderrAccumulator
        )

        let stdout = Self.lineStream(
            from: stdoutPipe.fileHandleForReading,
            onEOF: { [weak process] in
                guard let process else { return nil }
                process.waitUntilExit()
                let exitCode = process.terminationStatus
                if exitCode != 0 {
                    let stderrText = await stderrAccumulator.joined()
                    return ProcessStreamError.unexpectedTermination(
                        exitCode: exitCode,
                        stderr: stderrText.isEmpty ? nil : stderrText
                    )
                }
                return nil
            }
        )

        let writeLine: @Sendable (String) async throws -> Void = { [weak stdinPipe] line in
            guard let pipe = stdinPipe else {
                throw ProcessStreamError.notRunning
            }
            let data = Data((line + "\n").utf8)
            do {
                try pipe.fileHandleForWriting.write(contentsOf: data)
            } catch {
                throw ProcessStreamError.stdinWriteFailed(message: error.localizedDescription)
            }
        }

        let closeStdin: @Sendable () async -> Void = { [weak stdinPipe] in
            try? stdinPipe?.fileHandleForWriting.close()
        }

        let terminate: @Sendable () async -> Void = { [weak process] in
            process?.terminate()
        }

        let isRunning: @Sendable () async -> Bool = { [weak process] in
            process?.isRunning ?? false
        }

        return ProcessHandle(
            stdout: stdout,
            stderr: stderr,
            writeLine: writeLine,
            closeStdin: closeStdin,
            terminate: terminate,
            isRunning: isRunning
        )
    }
}

// MARK: - Line Stream from FileHandle

extension ProcessActor {
    /// Create an `AsyncThrowingStream<String, Error>` that yields lines from a
    /// `FileHandle` using `readabilityHandler`. This is more reliable than
    /// `FileHandle.bytes.lines` for long-running subprocesses that pause output.
    ///
    /// - Parameters:
    ///   - fileHandle: The pipe's reading end.
    ///   - accumulator: Optional stderr accumulator to record lines.
    ///   - onEOF: Optional async closure called on EOF; return an error to finish with, or nil.
    static func lineStream(
        from fileHandle: FileHandle,
        accumulator: StderrAccumulator? = nil,
        onEOF: (@Sendable () async -> (any Error)?)? = nil
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            // Buffer for incomplete lines (data between newlines)
            let buffer = LineBuffer()

            fileHandle.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    // EOF — flush remaining buffer and finish
                    fileHandle.readabilityHandler = nil
                    let remaining = buffer.flush()
                    for line in remaining {
                        if let acc = accumulator {
                            // Fire-and-forget append — ordering is best-effort for stderr
                            Task { await acc.append(line) }
                        }
                        continuation.yield(line)
                    }
                    // Check exit code if requested
                    if let onEOF {
                        Task {
                            if let error = await onEOF() {
                                continuation.finish(throwing: error)
                            } else {
                                continuation.finish()
                            }
                        }
                    } else {
                        continuation.finish()
                    }
                } else {
                    let lines = buffer.append(data)
                    for line in lines {
                        if let acc = accumulator {
                            Task { await acc.append(line) }
                        }
                        continuation.yield(line)
                    }
                }
            }

            continuation.onTermination = { @Sendable _ in
                fileHandle.readabilityHandler = nil
            }
        }
    }
}

// MARK: - Line Buffer

/// Thread-safe line buffer that accumulates data chunks and splits on newlines.
private final class LineBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var partial = Data()

    /// Append new data and return any complete lines.
    func append(_ data: Data) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        partial.append(data)
        return extractLines()
    }

    /// Flush any remaining partial line.
    func flush() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        guard !partial.isEmpty else { return [] }
        let remaining = String(data: partial, encoding: .utf8) ?? ""
        partial.removeAll()
        return remaining.isEmpty ? [] : [remaining]
    }

    private func extractLines() -> [String] {
        guard let string = String(data: partial, encoding: .utf8) else { return [] }
        var lines: [String] = []
        let parts = string.split(separator: "\n", omittingEmptySubsequences: false)
        // All parts except the last are complete lines
        for i in 0..<(parts.count - 1) {
            lines.append(String(parts[i]))
        }
        // Keep the last part as partial (may be incomplete)
        let lastPart = parts.last ?? ""
        partial = Data(lastPart.utf8)
        return lines
    }
}

// MARK: - Stderr Accumulator

private actor StderrAccumulator {
    private var lines: [String] = []

    func append(_ line: String) {
        lines.append(line)
    }

    func joined() -> String {
        lines.joined(separator: "\n")
    }
}
