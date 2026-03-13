//
//  AnthropicProvider.swift
//  SidePiece
//
//  Anthropic Messages API provider implementation.
//

import Foundation
import UniformTypeIdentifiers

/// Anthropic Messages API provider
public struct AnthropicProvider: AIProvider, Sendable {
    public let id: String = "anthropic"
    public let modelId: String
    public let apiKey: String
    public let baseURL: URL
    public let anthropicVersion: String

    private let http: HTTPStreamClient
    private let assetLoader: AssetLoader
    private let hooks: StreamHooks

    public init(
        modelId: String,
        apiKey: String,
        baseURL: URL = URL(string: "https://api.anthropic.com")!,
        anthropicVersion: String = "2023-06-01",
        hooks: StreamHooks = .default
    ) {
        self.modelId = modelId
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.anthropicVersion = anthropicVersion
        self.http = HTTPStreamClient(hooks: hooks)
        self.assetLoader = AssetLoader()
        self.hooks = hooks
    }

    public func stream(
        items: [ConversationItem],
        options: LLMRequestOptions
    ) -> AsyncThrowingStream<LLMStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try await buildRequest(items: items, options: options)
                    let sse = await http.streamSSE(request: request)

                    var toolArgsById: [String: String] = [:]
                    var toolNamesById: [String: String] = [:]
                    var blockIndexToToolId: [Int: String] = [:]
                    var usage: TokenUsage?
                    var stopReason: String?

                    for try await event in sse {
                        guard let data = event.data else { continue }

                        let json = try JSONDecoder().decode(JSONValue.self, from: Data(data.utf8))
                        guard case let .object(obj) = json else { continue }

                        let type = obj["type"]?.stringValue ?? ""

                        switch type {
                        case "message_start":
                            if let msg = obj["message"]?.objectValue,
                               let u = msg["usage"]?.objectValue {
                                let input = u["input_tokens"]?.intValue ?? 0
                                let output = u["output_tokens"]?.intValue ?? 0
                                let cacheRead = u["cache_read_input_tokens"]?.intValue ?? 0
                                let cacheWrite = u["cache_creation_input_tokens"]?.intValue ?? 0
                                usage = TokenUsage(
                                    promptTokens: input,
                                    completionTokens: output,
                                    cacheReadTokens: cacheRead,
                                    cacheWriteTokens: cacheWrite
                                )
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

                        case "error":
                            // Anthropic's error structure: { type: "error", error: { type: "...", message: "..." } }
                            let errorObj = obj["error"]?.objectValue
                            let code = errorObj?["type"]?.stringValue ?? "API_ERROR"
                            let msg = errorObj?["message"]?.stringValue ?? obj["message"]?.stringValue ?? "Anthropic error"
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
                        llmError = LLMError(code: "STREAM_FAILED", message: "Streaming failed", underlying: String(describing: error))
                    }
                    continuation.yield(.finished(usage: nil, finishReason: .error(llmError)))
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    // MARK: - Request Building

    private func buildRequest(items: [ConversationItem], options: LLMRequestOptions) async throws -> URLRequest {
        let url = baseURL.appendingPathComponent("v1/messages")

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue(anthropicVersion, forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        let messagesJSON = try await encodeMessages(items: items)

        var body: [String: JSONValue] = [
            "model": .string(modelId),
            "stream": .bool(true),
            "messages": .array(messagesJSON)
        ]
        
        if let sys = options.systemPrompt {
            body["system"] = .string(sys)
        }
        if let temp = options.temperature {
            body["temperature"] = .double(temp)
        }
        if let maxOutputTokens = options.maxOutputTokens {
            body["max_tokens"] = .int(maxOutputTokens)
        }

        // Reasoning / thinking control
        if let effort = options.reasoningEffort {
            let isAdaptiveModel = modelId.contains("opus-4") || modelId.contains("sonnet-4")
            switch effort {
            case .none:
                body["thinking"] = .object([
                    "type": .string("disabled")
                ])
            case .low:
                body["thinking"] = .object([
                    "type": .string("enabled"),
                    "budget_tokens": .int(512)
                ])
            case .medium:
                body["thinking"] = .object([
                    "type": .string("enabled"),
                    "budget_tokens": .int(2048)
                ])
            case .high:
                body["thinking"] = .object([
                    "type": .string("enabled"),
                    "budget_tokens": .int(8192)
                ])
            case .max:
                // Adaptive models support higher budgets
                let budget = isAdaptiveModel ? 32768 : 16384
                body["thinking"] = .object([
                    "type": .string("enabled"),
                    "budget_tokens": .int(budget)
                ])
            }
        }

        // Prompt caching — attach cache_control to system prompt
        if let retention = options.cacheRetention, retention != .none,
           let sys = options.systemPrompt {
            body["system"] = .array([
                .object([
                    "type": .string("text"),
                    "text": .string(sys),
                    "cache_control": .object(["type": .string("ephemeral")])
                ])
            ])
        }

        // Tools
        if !options.tools.isEmpty {
            body["tools"] = .array(options.tools.map { tool in
                .object([
                    "name": .string(tool.name),
                    "description": .string(tool.description),
                    "input_schema": tool.parameters
                ])
            })
        }

        req.httpBody = try JSONEncoder().encode(JSONValue.object(body))
        return req
    }

    private func encodeMessages(items: [ConversationItem]) async throws -> [JSONValue] {
        var out: [[String: JSONValue]] = []

        func appendMessage(role: String, blocks: [JSONValue]) {
            out.append([
                "role": .string(role),
                "content": .array(blocks)
            ])
        }

        func ensureLastRole(_ role: String) -> Bool {
            guard let last = out.last, last["role"]?.stringValue == role else { return false }
            return true
        }

        for item in items {
            switch item {
            case .message(let role, let content):
                let blocks = try await encodeBlocks(from: content)
                let roleStr = (role == .assistant) ? "assistant" : "user"
                appendMessage(role: roleStr, blocks: blocks)

            case .toolCall(let id, let name, let arguments):
                let block: JSONValue = .object([
                    "type": .string("tool_use"),
                    "id": .string(id),
                    "name": .string(name),
                    "input": (try? JSONValue.parse(jsonString: arguments)) ?? .object([:])
                ])

                if ensureLastRole("assistant") {
                    var last = out.removeLast()
                    var blocks = last["content"]?.arrayValue ?? []
                    blocks.append(block)
                    last["content"] = .array(blocks)
                    out.append(last)
                } else {
                    appendMessage(role: "assistant", blocks: [block])
                }

            case .toolResult(let id, let output):
                let block: JSONValue = .object([
                    "type": .string("tool_result"),
                    "tool_use_id": .string(id),
                    "content": .string(output)
                ])
                if ensureLastRole("user") {
                    var last = out.removeLast()
                    var blocks = last["content"]?.arrayValue ?? []
                    blocks.append(block)
                    last["content"] = .array(blocks)
                    out.append(last)
                } else {
                    appendMessage(role: "user", blocks: [block])
                }
            }
        }

        return out.map { .object($0) }
    }

    private func encodeBlocks(from parts: [ContentPart]) async throws -> [JSONValue] {
        var blocks: [JSONValue] = []

        for part in parts {
            switch part {
            case .text(let text):
                blocks.append(.object([
                    "type": .string("text"),
                    "text": .string(text)
                ]))

            case .image(let fileSource):
                let data = try await assetLoader.loadData(from: fileSource.url)
                let mt = fileSource.contentType.preferredMIMEType ?? MediaTypeDetector.detect(from: data) ?? "image/jpeg"
                blocks.append(.object([
                    "type": .string("image"),
                    "source": .object([
                        "type": .string("base64"),
                        "media_type": .string(mt),
                        "data": .string(data.base64EncodedString())
                    ])
                ]))

            case .file(let fileSource):
                let data = try await assetLoader.loadData(from: fileSource.url)
                let mt = fileSource.contentType.preferredMIMEType ?? "application/octet-stream"
                blocks.append(.object([
                    "type": .string("document"),
                    "source": .object([
                        "type": .string("base64"),
                        "media_type": .string(mt),
                        "data": .string(data.base64EncodedString())
                    ])
                ]))
            }
        }

        return blocks
    }
}
