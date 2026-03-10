//
//  ClaudeCodeProvider.swift
//  SidePiece
//
//  AIProvider implementation wrapping the Claude CLI in headless streaming mode.
//  Uses `claude -p --output-format stream-json --verbose` for NDJSON streaming.
//

import Dependencies
import Foundation

/// Actor for storing session ID across stream() calls for `--resume` support.
public actor ClaudeCodeSessionStore {
    public var sessionId: String?

    public init(sessionId: String? = nil) {
        self.sessionId = sessionId
    }
}

// MARK: - Error

public enum ClaudeCodeError: LocalizedError, Equatable, Sendable {
    case parseError(String)
    case processFailed(ProcessStreamError)
    case noPromptFound

    public var errorDescription: String? {
        switch self {
        case .parseError(let detail):
            "Claude Code parse error: \(detail)"
        case .processFailed(let error):
            "Claude Code process error: \(error.localizedDescription)"
        case .noPromptFound:
            "No user message found to send to Claude Code"
        }
    }
}

// MARK: - Provider

public struct ClaudeCodeProvider: AIProvider, Sendable {
    public let id: String = "claude-code"
    public let modelId: String
    let executablePath: String
    let sessionStore: ClaudeCodeSessionStore
    let dangerouslySkipPermissions: Bool

    public init(
        modelId: String,
        executablePath: String = "claude",
        sessionStore: ClaudeCodeSessionStore = ClaudeCodeSessionStore(),
        dangerouslySkipPermissions: Bool = true
    ) {
        self.modelId = modelId
        self.executablePath = executablePath
        self.sessionStore = sessionStore
        self.dangerouslySkipPermissions = dangerouslySkipPermissions
    }

    public func stream(
        items: [ConversationItem],
        options: LLMRequestOptions
    ) -> AsyncThrowingStream<LLMStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    // Extract the last user message as the prompt
                    guard let prompt = extractPrompt(from: items) else {
                        let error = ClaudeCodeError.noPromptFound
                        continuation.yield(.finished(usage: nil, finishReason: .error(
                            LLMError(code: "NO_PROMPT", message: error.localizedDescription)
                        )))
                        continuation.finish()
                        return
                    }

                    // Build CLI arguments
                    var args = ["-p", prompt, "--output-format", "stream-json", "--verbose"]

                    if let sessionId = await sessionStore.sessionId {
                        args.append(contentsOf: ["--resume", sessionId])
                    }

                    if dangerouslySkipPermissions {
                        args.append("--dangerously-skip-permissions")
                    }

                    args.append(contentsOf: ["--model", modelId])

                    if let systemPrompt = options.systemPrompt {
                        args.append(contentsOf: ["--system-prompt", systemPrompt])
                    }

                    let configuration = ProcessConfiguration(
                        executablePath: executablePath,
                        arguments: args
                    )

                    @Dependency(\.processStreamClient) var processClient
                    let handle: ProcessHandle
                    do {
                        handle = try await processClient.spawn(configuration)
                    } catch let error as ProcessStreamError {
                        let llmError = LLMError(
                            code: "PROCESS_SPAWN_FAILED",
                            message: error.localizedDescription
                        )
                        continuation.yield(.finished(usage: nil, finishReason: .error(llmError)))
                        continuation.finish()
                        return
                    }

                    // Close stdin immediately — claude -p gets the prompt via CLI args
                    // and reads stdin until EOF, so an open pipe would hang forever.
                    await handle.closeStdin()

                    // Drain stderr in background so the pipe doesn't block
                    _ = Task {
                        for try await line in handle.stderr {
                            print("[ClaudeCode] stderr: \(String(line.prefix(200)))")
                        }
                    }

                    let events = NDJSONParser.parse(handle.stdout)
                    var usage: TokenUsage?
                    var eventCount = 0

                    for try await json in events {
                        guard case let .object(obj) = json else { continue }
                        let type = obj["type"]?.stringValue ?? ""
                        eventCount += 1
                        if eventCount <= 5 { print("[ClaudeCode] event #\(eventCount): type=\(type)") }

                        switch type {
                        // Claude Code CLI emits a "system" init event with session metadata
                        case "system":
                            if let sessionId = obj["session_id"]?.stringValue {
                                await sessionStore.update(sessionId: sessionId)
                            }

                        // "assistant" events contain the full message with content blocks
                        case "assistant":
                            if let msg = obj["message"]?.objectValue {
                                // Extract usage
                                if let u = msg["usage"]?.objectValue {
                                    let input = u["input_tokens"]?.intValue ?? 0
                                    let output = u["output_tokens"]?.intValue ?? 0
                                    let cacheCreation = u["cache_creation_input_tokens"]?.intValue ?? 0
                                    let cacheRead = u["cache_read_input_tokens"]?.intValue ?? 0
                                    usage = TokenUsage(
                                        promptTokens: input + cacheCreation + cacheRead,
                                        completionTokens: output
                                    )
                                }

                                // Process content blocks
                                if let content = msg["content"]?.arrayValue {
                                    for block in content {
                                        guard let blockObj = block.objectValue,
                                              let blockType = blockObj["type"]?.stringValue else { continue }

                                        switch blockType {
                                        case "text":
                                            let text = blockObj["text"]?.stringValue ?? ""
                                            if !text.isEmpty {
                                                continuation.yield(.textDelta(text))
                                            }

                                        case "thinking":
                                            let thinking = blockObj["thinking"]?.stringValue ?? ""
                                            if !thinking.isEmpty {
                                                continuation.yield(.reasoningDelta(thinking))
                                            }

                                        case "tool_use":
                                            let toolId = blockObj["id"]?.stringValue ?? "call_\(UUID().uuidString)"
                                            let name = blockObj["name"]?.stringValue ?? "tool"
                                            let input = blockObj["input"]
                                            let args: String
                                            if let input {
                                                // Encode the input back to JSON string
                                                if let data = try? JSONEncoder().encode(input) {
                                                    args = String(data: data, encoding: .utf8) ?? "{}"
                                                } else {
                                                    args = "{}"
                                                }
                                            } else {
                                                args = "{}"
                                            }
                                            continuation.yield(.toolCallStart(id: toolId, name: name))
                                            continuation.yield(.toolCallDelta(id: toolId, args: args))
                                            continuation.yield(.toolCallEnd(id: toolId, name: name, arguments: args))

                                        default:
                                            break
                                        }
                                    }
                                }
                            }

                        // "result" is the final event with session and usage info
                        case "result":
                            if let sessionId = obj["session_id"]?.stringValue {
                                await sessionStore.update(sessionId: sessionId)
                            }
                            if let u = obj["usage"]?.objectValue {
                                let input = u["input_tokens"]?.intValue ?? 0
                                let output = u["output_tokens"]?.intValue ?? 0
                                usage = TokenUsage(promptTokens: input, completionTokens: output)
                            }
                            let isError = obj["is_error"]?.boolValue ?? false
                            if isError {
                                let msg = obj["result"]?.stringValue ?? "Claude Code error"
                                let error = LLMError(code: "CLAUDE_CODE_ERROR", message: msg)
                                continuation.yield(.finished(usage: usage, finishReason: .error(error)))
                            } else {
                                continuation.yield(.finished(usage: usage, finishReason: .stop))
                            }

                        case "error":
                            let errorObj = obj["error"]?.objectValue
                            let code = errorObj?["type"]?.stringValue ?? "CLAUDE_CODE_ERROR"
                            let msg = errorObj?["message"]?.stringValue ?? obj["message"]?.stringValue ?? "Claude Code error"
                            let error = LLMError(code: code, message: msg)
                            continuation.yield(.finished(usage: usage, finishReason: .error(error)))

                        default:
                            // Ignore rate_limit_event and other unknown types
                            break
                        }
                    }

                    continuation.finish()
                } catch {
                    let llmError: LLMError
                    if let e = error as? LLMError {
                        llmError = e
                    } else {
                        llmError = LLMError(
                            code: "STREAM_FAILED",
                            message: "Streaming failed",
                            underlying: String(describing: error)
                        )
                    }
                    continuation.yield(.finished(usage: nil, finishReason: .error(llmError)))
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    // MARK: - Helpers

    private func extractPrompt(from items: [ConversationItem]) -> String? {
        // Walk backwards to find the last user message
        for item in items.reversed() {
            if case let .message(role, content) = item, role == .user {
                return content.compactMap { part in
                    if case let .text(text) = part { return text }
                    return nil
                }.joined(separator: "\n")
            }
        }
        return nil
    }
}

// MARK: - Session Store Extension

extension ClaudeCodeSessionStore {
    func update(sessionId: String) {
        self.sessionId = sessionId
    }
}
