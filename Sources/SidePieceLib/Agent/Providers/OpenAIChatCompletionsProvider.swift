//
//  OpenAIChatCompletionsProvider.swift
//  SidePiece
//
//  OpenAI Chat Completions API provider. This unlocks all OpenAI-compatible
//  endpoints: Groq, Together, Ollama, xAI, OpenRouter, Mistral, and others.
//

import Foundation
import UniformTypeIdentifiers

/// Configuration flags for OpenAI-compatible API quirks.
/// Different providers have subtle incompatibilities that these flags address.
public struct OpenAICompletionsCompat: Sendable, Equatable {

    /// The field name used for max tokens (`"max_tokens"` vs `"max_completion_tokens"`).
    public var maxTokensField: MaxTokensField

    /// Whether the provider supports the `"developer"` role (newer OpenAI convention).
    /// When `false`, system prompts use the `"system"` role instead.
    public var supportsDeveloperRole: Bool

    /// Whether the provider supports the `reasoning_effort` parameter.
    public var supportsReasoningEffort: Bool

    /// Whether tool results must include a `"name"` field alongside `"tool_call_id"`.
    public var requiresToolResultName: Bool

    /// Whether the provider requires an assistant message after a tool result message
    /// (some providers reject tool-result → user sequences).
    public var requiresAssistantAfterToolResult: Bool

    /// Whether thinking/reasoning blocks should be converted to plain text
    /// (for providers that don't support native thinking content).
    public var requiresThinkingAsText: Bool

    /// Whether the provider supports the `"store"` parameter.
    public var supportsStore: Bool

    /// Whether the provider supports `stream_options` for streaming usage.
    public var supportsStreamOptions: Bool

    public enum MaxTokensField: String, Sendable, Equatable {
        case maxTokens = "max_tokens"
        case maxCompletionTokens = "max_completion_tokens"
    }

    public init(
        maxTokensField: MaxTokensField = .maxTokens,
        supportsDeveloperRole: Bool = false,
        supportsReasoningEffort: Bool = false,
        requiresToolResultName: Bool = false,
        requiresAssistantAfterToolResult: Bool = false,
        requiresThinkingAsText: Bool = true,
        supportsStore: Bool = false,
        supportsStreamOptions: Bool = true
    ) {
        self.maxTokensField = maxTokensField
        self.supportsDeveloperRole = supportsDeveloperRole
        self.supportsReasoningEffort = supportsReasoningEffort
        self.requiresToolResultName = requiresToolResultName
        self.requiresAssistantAfterToolResult = requiresAssistantAfterToolResult
        self.requiresThinkingAsText = requiresThinkingAsText
        self.supportsStore = supportsStore
        self.supportsStreamOptions = supportsStreamOptions
    }

    /// Standard OpenAI API (GPT-4o, o-series, etc.)
    public static let openAI = OpenAICompletionsCompat(
        maxTokensField: .maxCompletionTokens,
        supportsDeveloperRole: true,
        supportsReasoningEffort: true,
        supportsStore: true,
        supportsStreamOptions: true
    )

    /// Groq-hosted models
    public static let groq = OpenAICompletionsCompat(
        maxTokensField: .maxTokens,
        supportsStreamOptions: false
    )

    /// Together AI
    public static let together = OpenAICompletionsCompat(
        maxTokensField: .maxTokens
    )

    /// xAI (Grok)
    public static let xai = OpenAICompletionsCompat(
        maxTokensField: .maxTokens
    )

    /// OpenRouter (gateway to many providers)
    public static let openRouter = OpenAICompletionsCompat(
        maxTokensField: .maxTokens,
        requiresToolResultName: true
    )

    /// Mistral API (via OpenAI-compatible endpoint)
    public static let mistral = OpenAICompletionsCompat(
        maxTokensField: .maxTokens,
        requiresToolResultName: true
    )

    /// Local Ollama server
    public static let ollama = OpenAICompletionsCompat(
        maxTokensField: .maxTokens,
        supportsStreamOptions: false
    )

    /// Generic default for unknown OpenAI-compatible endpoints
    public static let `default` = OpenAICompletionsCompat()
}

// MARK: - Provider

/// OpenAI Chat Completions API provider (`/v1/chat/completions`).
///
/// This provider speaks the widely-adopted Chat Completions wire format
/// used by OpenAI and dozens of compatible endpoints. Use `OpenAICompletionsCompat`
/// to handle provider-specific quirks.
public struct OpenAIChatCompletionsProvider: AIProvider, Sendable {
    public let id: String
    public let modelId: String
    public let apiKey: String
    public let baseURL: URL
    public let compat: OpenAICompletionsCompat

    private let http: HTTPStreamClient
    private let assetLoader: AssetLoader
    private let hooks: StreamHooks

    public init(
        id: String = "openai-completions",
        modelId: String,
        apiKey: String,
        baseURL: URL = URL(string: "https://api.openai.com/v1")!,
        compat: OpenAICompletionsCompat = .default,
        hooks: StreamHooks = .default
    ) {
        self.id = id
        self.modelId = modelId
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.compat = compat
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

                    var toolCallArgs: [Int: String] = [:]
                    var toolCallNames: [Int: String] = [:]
                    var toolCallIds: [Int: String] = [:]
                    var usage: TokenUsage?

                    for try await event in sse {
                        guard let data = event.data else { continue }

                        if data == "[DONE]" {
                            let finishReason: FinishReason = toolCallIds.isEmpty ? .stop : .toolCalls
                            continuation.yield(.finished(usage: usage, finishReason: finishReason))
                            continuation.finish()
                            return
                        }

                        let json = try JSONDecoder().decode(JSONValue.self, from: Data(data.utf8))
                        guard case let .object(obj) = json else { continue }

                        // Handle API errors
                        if let errObj = obj["error"]?.objectValue, let msg = errObj["message"]?.stringValue {
                            let code = errObj["code"]?.stringValue ?? errObj["type"]?.stringValue ?? "API_ERROR"
                            continuation.yield(.finished(
                                usage: usage,
                                finishReason: .error(LLMError(code: code, message: msg))
                            ))
                            continue
                        }

                        // Parse usage from stream (when stream_options.include_usage is set)
                        if let usageObj = obj["usage"]?.objectValue {
                            let input = usageObj["prompt_tokens"]?.intValue ?? 0
                            let output = usageObj["completion_tokens"]?.intValue ?? 0
                            var details: [String: Int] = [:]
                            if let reasoning = usageObj["completion_tokens_details"]?.objectValue?["reasoning_tokens"]?.intValue {
                                details["reasoning_tokens"] = reasoning
                            }
                            usage = TokenUsage(promptTokens: input, completionTokens: output, details: details)
                        }

                        // Parse choices
                        guard let choices = obj["choices"]?.arrayValue,
                              let choice = choices.first?.objectValue else { continue }

                        // Check finish_reason
                        if let reason = choice["finish_reason"]?.stringValue, reason != "null" {
                            let finishReason: FinishReason = switch reason {
                            case "stop": .stop
                            case "tool_calls": .toolCalls
                            case "length": .length
                            case "content_filter": .contentFilter
                            default: .unknown
                            }

                            // Flush any pending tool calls
                            for (index, callId) in toolCallIds.sorted(by: { $0.key < $1.key }) {
                                let name = toolCallNames[index] ?? "tool"
                                let args = toolCallArgs[index] ?? "{}"
                                continuation.yield(.toolCallEnd(id: callId, name: name, arguments: args))
                            }

                            continuation.yield(.finished(usage: usage, finishReason: finishReason))
                            continue
                        }

                        // Parse delta
                        guard let delta = choice["delta"]?.objectValue else { continue }

                        // Text content
                        if let content = delta["content"]?.stringValue, !content.isEmpty {
                            continuation.yield(.textDelta(content))
                        }

                        // Reasoning content (OpenAI o-series models)
                        if let reasoning = delta["reasoning_content"]?.stringValue, !reasoning.isEmpty {
                            continuation.yield(.reasoningDelta(reasoning))
                        }

                        // Tool calls
                        if let toolCalls = delta["tool_calls"]?.arrayValue {
                            for tc in toolCalls {
                                guard let tcObj = tc.objectValue,
                                      let index = tcObj["index"]?.intValue else { continue }

                                // New tool call
                                if let function = tcObj["function"]?.objectValue {
                                    if let name = function["name"]?.stringValue {
                                        let callId = tcObj["id"]?.stringValue ?? "call_\(UUID().uuidString)"
                                        toolCallIds[index] = callId
                                        toolCallNames[index] = name
                                        toolCallArgs[index] = ""
                                        continuation.yield(.toolCallStart(id: callId, name: name))
                                    }

                                    if let argsDelta = function["arguments"]?.stringValue, !argsDelta.isEmpty {
                                        toolCallArgs[index, default: ""] += argsDelta
                                        if let callId = toolCallIds[index] {
                                            continuation.yield(.toolCallDelta(id: callId, args: argsDelta))
                                        }
                                    }
                                }
                            }
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

    // MARK: - Request Building

    private func buildRequest(items: [ConversationItem], options: LLMRequestOptions) async throws -> URLRequest {
        let url = baseURL.appendingPathComponent("chat/completions")

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        var body: [String: JSONValue] = [
            "model": .string(modelId),
            "stream": .bool(true)
        ]

        // Stream options for usage tracking
        if compat.supportsStreamOptions {
            body["stream_options"] = .object(["include_usage": .bool(true)])
        }

        if compat.supportsStore {
            body["store"] = .bool(false)
        }

        if let t = options.temperature {
            body["temperature"] = .double(t)
        }
        if let m = options.maxOutputTokens {
            body[compat.maxTokensField.rawValue] = .int(m)
        }

        // Reasoning effort (.max maps to "high" for OpenAI-compatible APIs)
        if let effort = options.reasoningEffort, compat.supportsReasoningEffort {
            let apiEffort = (effort == .max) ? "high" : effort.rawValue
            body["reasoning_effort"] = .string(apiEffort)
        }

        // Service tier
        if let tier = options.serviceTier {
            body["service_tier"] = .string(tier.rawValue)
        }

        // Tools
        if !options.tools.isEmpty {
            body["tools"] = .array(options.tools.map { tool in
                .object([
                    "type": .string("function"),
                    "function": .object([
                        "name": .string(tool.name),
                        "description": .string(tool.description),
                        "parameters": tool.parameters
                    ])
                ])
            })
        }

        // Messages
        let messages = try await encodeMessages(items: items, systemPrompt: options.systemPrompt)
        body["messages"] = .array(messages)

        let data = try JSONEncoder().encode(JSONValue.object(body))
        req.httpBody = data
        return req
    }

    private func encodeMessages(
        items: [ConversationItem],
        systemPrompt: String?
    ) async throws -> [JSONValue] {
        var messages: [JSONValue] = []

        // System prompt
        if let sys = systemPrompt {
            let role = compat.supportsDeveloperRole ? "developer" : "system"
            messages.append(.object([
                "role": .string(role),
                "content": .string(sys)
            ]))
        }

        // Track tool call names for tool result messages
        var toolCallNameById: [String: String] = [:]

        for item in items {
            switch item {
            case .message(let role, let content):
                let roleStr: String = switch role {
                case .system: compat.supportsDeveloperRole ? "developer" : "system"
                case .user: "user"
                case .assistant: "assistant"
                case .tool: "tool"
                }
                let parts = try await encodeContent(content)
                if parts.count == 1, let single = parts.first?.objectValue,
                   single["type"]?.stringValue == "text" {
                    // Single text content — use plain string format
                    messages.append(.object([
                        "role": .string(roleStr),
                        "content": .string(single["text"]?.stringValue ?? "")
                    ]))
                } else {
                    messages.append(.object([
                        "role": .string(roleStr),
                        "content": .array(parts)
                    ]))
                }

            case .toolCall(let id, let name, let arguments):
                toolCallNameById[id] = name
                let toolCallObj: JSONValue = .object([
                    "id": .string(id),
                    "type": .string("function"),
                    "function": .object([
                        "name": .string(name),
                        "arguments": .string(arguments)
                    ])
                ])

                // Append to existing assistant message or create new one
                if let last = messages.last?.objectValue,
                   last["role"]?.stringValue == "assistant" {
                    var msg = messages.removeLast()
                    var obj = msg.objectValue ?? [:]
                    var calls = obj["tool_calls"]?.arrayValue ?? []
                    calls.append(toolCallObj)
                    obj["tool_calls"] = .array(calls)
                    messages.append(.object(obj))
                } else {
                    messages.append(.object([
                        "role": .string("assistant"),
                        "content": .null,
                        "tool_calls": .array([toolCallObj])
                    ]))
                }

            case .toolResult(let id, let output):
                var msg: [String: JSONValue] = [
                    "role": .string("tool"),
                    "tool_call_id": .string(id),
                    "content": .string(output)
                ]
                if compat.requiresToolResultName, let name = toolCallNameById[id] {
                    msg["name"] = .string(name)
                }
                messages.append(.object(msg))
            }
        }

        return messages
    }

    private func encodeContent(_ parts: [ContentPart]) async throws -> [JSONValue] {
        var result: [JSONValue] = []

        for part in parts {
            switch part {
            case .text(let text):
                result.append(.object([
                    "type": .string("text"),
                    "text": .string(text)
                ]))

            case .image(let fileSource):
                let urlString = try await encodeImageURL(fileSource)
                result.append(.object([
                    "type": .string("image_url"),
                    "image_url": .object([
                        "url": .string(urlString)
                    ])
                ]))

            case .file(let fileSource):
                let data = try await assetLoader.loadData(from: fileSource.url)
                let text = String(decoding: data, as: UTF8.self)
                result.append(.object([
                    "type": .string("text"),
                    "text": .string("[File: \(fileSource.url.lastPathComponent)]\n\(text)")
                ]))
            }
        }

        return result
    }

    private func encodeImageURL(_ fileSource: FileSource) async throws -> String {
        if fileSource.url.scheme == "https" {
            return fileSource.url.absoluteString
        }

        let data = try await assetLoader.loadData(from: fileSource.url)
        let media = fileSource.contentType.preferredMIMEType
            ?? MediaTypeDetector.detect(from: data) ?? "image/jpeg"
        let base64 = data.base64EncodedString()
        return MediaTypeDetector.makeDataURL(mediaType: media, base64: base64)
    }
}
