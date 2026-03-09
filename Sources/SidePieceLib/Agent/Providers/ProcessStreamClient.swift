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
    
    public init(
        stdout: AsyncThrowingStream<String, Error>,
        writeLine: @Sendable @escaping (String) async throws -> Void,
        terminate: @Sendable @escaping () async -> Void,
        isRunning: @Sendable @escaping () async -> Bool
    ) {
        self.stdout = stdout
        self.writeLine = writeLine
        self.terminate = terminate
        self.isRunning = isRunning
    }
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

    private static func enrichedEnvironment(custom: [String: String]?) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        if let custom { for (k, v) in custom { env[k] = v } }

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
