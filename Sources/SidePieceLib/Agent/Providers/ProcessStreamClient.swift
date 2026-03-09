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
    public let writeLine: @Sendable (String) async throws -> Void
    public let terminate: @Sendable () async -> Void
    public let isRunning: @Sendable () async -> Bool
}

public enum ProcessStreamError: LocalizedError, Equatable, Sendable {
    case executableNotFound(path: String)
    case spawnFailed(message: String)
    case notRunning
    case stdinWriteFailed(message: String)
    case unexpectedTermination(exitCode: Int32)

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
        case .unexpectedTermination(let exitCode):
            "Process terminated unexpectedly with exit code \(exitCode)"
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

    func spawn(configuration: ProcessConfiguration) throws(ProcessStreamError) -> ProcessHandle {
        let process = Process()
        let stdoutPipe = Pipe()
        let stdinPipe = Pipe()

        // Resolve executable path via PATH if not absolute
        let resolvedPath: String
        if configuration.executablePath.hasPrefix("/") {
            resolvedPath = configuration.executablePath
        } else {
            // Use /usr/bin/env to resolve from PATH
            resolvedPath = "/usr/bin/env"
        }

        guard FileManager.default.fileExists(atPath: resolvedPath) else {
            throw .executableNotFound(path: resolvedPath)
        }

        if resolvedPath == "/usr/bin/env" {
            process.executableURL = URL(fileURLWithPath: resolvedPath)
            process.arguments = [configuration.executablePath] + configuration.arguments
        } else {
            process.executableURL = URL(fileURLWithPath: resolvedPath)
            process.arguments = configuration.arguments
        }

        if let env = configuration.environment {
            // Merge with current environment
            var merged = ProcessInfo.processInfo.environment
            for (key, value) in env { merged[key] = value }
            process.environment = merged
        }
        if let wd = configuration.workingDirectory {
            process.currentDirectoryURL = wd
        }

        process.standardOutput = stdoutPipe
        process.standardInput = stdinPipe

        do {
            try process.run()
        } catch {
            throw .spawnFailed(message: error.localizedDescription)
        }

        self.process = process
        self.stdinPipe = stdinPipe

        let stdout = AsyncThrowingStream<String, Error> { continuation in
            let task = Task {
                do {
                    for try await line in stdoutPipe.fileHandleForReading.bytes.lines {
                        continuation.yield(line)
                    }
                    // Process finished — check exit code
                    process.waitUntilExit()
                    let exitCode = process.terminationStatus
                    if exitCode != 0 {
                        continuation.finish(
                            throwing: ProcessStreamError.unexpectedTermination(exitCode: exitCode)
                        )
                    } else {
                        continuation.finish()
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }

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

        let terminate: @Sendable () async -> Void = { [weak process] in
            process?.terminate()
        }

        let isRunning: @Sendable () async -> Bool = { [weak process] in
            process?.isRunning ?? false
        }

        return ProcessHandle(
            stdout: stdout,
            writeLine: writeLine,
            terminate: terminate,
            isRunning: isRunning
        )
    }
}
