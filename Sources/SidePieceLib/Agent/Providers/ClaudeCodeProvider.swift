//
//  ClaudeCodeProvider.swift
//  SidePiece
//
//  AIProvider implementation wrapping the Claude CLI in headless streaming mode.
//  Uses `claude -p --output-format stream-json` for unidirectional NDJSON streaming.
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
                    var args = ["-p", prompt, "--output-format", "stream-json"]

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

                    let events = NDJSONParser.parse(handle.stdout)

                    // Track state for Anthropic-compatible event mapping
                    var toolArgsById: [String: String] = [:]
                    var toolNamesById: [String: String] = [:]
                    var blockIndexToToolId: [Int: String] = [:]
                    var usage: TokenUsage?
                    var stopReason: String?

                    for try await json in events {
                        guard case let .object(obj) = json else { continue }
                        let type = obj["type"]?.stringValue ?? ""

                        switch type {
                        // Claude Code emits an `init` event with session metadata
                        case "system":
                            if let sessionId = obj["session_id"]?.stringValue {
                                await sessionStore.update(sessionId: sessionId)
                            }

                        // Reuse Anthropic event mapping — Claude Code's stream-json
                        // format uses the same event types as the Anthropic Messages API.
                        case "message_start":
                            if let msg = obj["message"]?.objectValue,
                               let u = msg["usage"]?.objectValue {
                                let input = u["input_tokens"]?.intValue ?? 0
                                let output = u["output_tokens"]?.intValue ?? 0
                                usage = TokenUsage(promptTokens: input, completionTokens: output)
                            }

                        case "content_block_start":
                            let index = obj["index"]?.intValue ?? 0
                            if let block = obj["content_block"]?.objectValue,
                               let bType = block["type"]?.stringValue {
                                if bType == "tool_use" {
                                    let toolId = block["id"]?.stringValue ?? "call_\(UUID().uuidString)"
                                    let name = block["name"]?.stringValue ?? "tool"
                                    blockIndexToToolId[index] = toolId
                                    toolArgsById[toolId] = ""
                                    toolNamesById[toolId] = name
                                    continuation.yield(.toolCallStart(id: toolId, name: name))
                                }
                            }

                        case "content_block_delta":
                            let index = obj["index"]?.intValue ?? 0
                            guard let delta = obj["delta"]?.objectValue else { break }
                            let dType = delta["type"]?.stringValue ?? ""

                            if dType == "text_delta" {
                                let text = delta["text"]?.stringValue ?? ""
                                if !text.isEmpty {
                                    continuation.yield(.textDelta(text))
                                }
                            } else if dType == "input_json_delta" {
                                let frag = delta["partial_json"]?.stringValue ?? ""
                                if let toolId = blockIndexToToolId[index], !frag.isEmpty {
                                    toolArgsById[toolId, default: ""] += frag
                                    continuation.yield(.toolCallDelta(id: toolId, args: frag))
                                }
                            } else if dType == "thinking_delta" {
                                let t = delta["thinking"]?.stringValue ?? ""
                                if !t.isEmpty {
                                    continuation.yield(.reasoningDelta(t))
                                }
                            }

                        case "content_block_stop":
                            let index = obj["index"]?.intValue ?? 0
                            if let toolId = blockIndexToToolId[index] {
                                let args = toolArgsById[toolId] ?? "{}"
                                let name = toolNamesById[toolId] ?? "tool"
                                continuation.yield(.toolCallEnd(id: toolId, name: name, arguments: args))
                                blockIndexToToolId.removeValue(forKey: index)
                            }

                        case "message_delta":
                            if let u = obj["usage"]?.objectValue {
                                let input = u["input_tokens"]?.intValue ?? usage?.promptTokens ?? 0
                                let output = u["output_tokens"]?.intValue ?? usage?.completionTokens ?? 0
                                usage = TokenUsage(promptTokens: input, completionTokens: output)
                            }
                            if let delta = obj["delta"]?.objectValue,
                               let reason = delta["stop_reason"]?.stringValue {
                                stopReason = reason
                            }

                        case "message_stop":
                            let finishReason: FinishReason = switch stopReason {
                            case "tool_use": .toolCalls
                            case "max_tokens": .length
                            case "content_filter": .contentFilter
                            default: .stop
                            }
                            continuation.yield(.finished(usage: usage, finishReason: finishReason))

                        case "result":
                            // Final result event — update usage if present
                            if let input = obj["input_tokens"]?.intValue,
                               let output = obj["output_tokens"]?.intValue {
                                usage = TokenUsage(promptTokens: input, completionTokens: output)
                            }
                            if let sessionId = obj["session_id"]?.stringValue {
                                await sessionStore.update(sessionId: sessionId)
                            }

                        case "error":
                            let errorObj = obj["error"]?.objectValue
                            let code = errorObj?["type"]?.stringValue ?? "CLAUDE_CODE_ERROR"
                            let msg = errorObj?["message"]?.stringValue ?? obj["message"]?.stringValue ?? "Claude Code error"
                            let error = LLMError(code: code, message: msg)
                            continuation.yield(.finished(usage: usage, finishReason: .error(error)))

                        default:
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
