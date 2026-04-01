//
//  Bash.swift
//  SidePiece
//

import Foundation

// MARK: - Tool

public struct BashTool: TypedTool {
    public let name = "bash"
    public let safetyLevel: ToolSafetyLevel = .supervised
    public let description =
        "Execute a bash command in the project directory. " +
        "Use this for running build commands, tests, git operations, " +
        "installing dependencies, or any shell command needed to complete the task. " +
        "Commands run with a timeout and output is truncated if too large."

    // MARK: - Input

    public struct Input: ToolInput {
        /// The shell command to execute.
        public let command: String
        /// Optional timeout in seconds. Defaults to 120.
        public let timeout: Int?

        public static var schema: JSONValue {
            .objectSchema(
                properties: [
                    "command": .stringProperty(
                        description: "The bash command to execute"
                    ),
                    "timeout": .intProperty(
                        description: "Timeout in seconds (default: 120, max: 600)"
                    ),
                ],
                required: ["command"]
            )
        }
    }

    // MARK: - Output

    public struct Output: Encodable, ToolOutput, Sendable {
        public let exitCode: Int32
        public let stdout: String
        public let stderr: String
    }

    static let maxOutputSize = 100_000

    // MARK: - Execute

    public func execute(_ input: Input, projectURL: URL) async throws -> Output {
        let timeoutSeconds = min(max(input.timeout ?? 120, 1), 600)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", input.command]
        process.currentDirectoryURL = projectURL

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw ToolExecutionError.executionFailed(
                message: "Failed to start process: \(error.localizedDescription)"
            )
        }

        // Bridge the blocking process wait into structured concurrency.
        // nonisolated(unsafe) is used for Process (NSObject, non-Sendable)
        // because terminate() is thread-safe and we ensure single-owner semantics.
        nonisolated(unsafe) let unsafeProcess = process

        let result = await withCheckedContinuation { (continuation: CheckedContinuation<(Int32, Bool), Never>) in
            let timer = DispatchSource.makeTimerSource(queue: .global())
            timer.schedule(deadline: .now() + .seconds(timeoutSeconds))
            timer.setEventHandler {
                unsafeProcess.terminate()
            }
            timer.resume()

            // terminationHandler fires on a background thread after the
            // process exits (either naturally or via terminate).
            unsafeProcess.terminationHandler = { proc in
                timer.cancel()
                let wasTimedOut = proc.terminationStatus == SIGTERM || proc.terminationReason == .uncaughtSignal
                continuation.resume(returning: (proc.terminationStatus, wasTimedOut))
            }
        }

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        var stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        var stderr = String(data: stderrData, encoding: .utf8) ?? ""

        if stdout.count > Self.maxOutputSize {
            stdout = String(stdout.prefix(Self.maxOutputSize)) + "\n... [output truncated]"
        }
        if stderr.count > Self.maxOutputSize {
            stderr = String(stderr.prefix(Self.maxOutputSize)) + "\n... [output truncated]"
        }
        if result.1 {
            stderr += "\n[Process timed out after \(timeoutSeconds)s and was terminated]"
        }

        return Output(
            exitCode: result.0,
            stdout: stdout,
            stderr: stderr
        )
    }
}

// MARK: - Tool Extension

extension Tool {
    public static let bash = Tool(BashTool())
}
