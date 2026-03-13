//
//  GeminiProvider.swift
//  SidePiece
//
//  Google Gemini API provider implementation.
//

import Foundation
import UniformTypeIdentifiers

/// Google Gemini API provider using the streamGenerateContent endpoint
public struct GeminiProvider: AIProvider, Sendable {
    public let id: String = "google"
    public let modelId: String
    public let apiKey: String
    public let baseURL: URL

    private let http: HTTPStreamClient
    private let assetLoader: AssetLoader
    private let hooks: StreamHooks

    public init(
        modelId: String,
        apiKey: String,
        baseURL: URL = URL(string: "https://generativelanguage.googleapis.com/v1beta")!,
        hooks: StreamHooks = .default
    ) {
        self.modelId = modelId
        self.apiKey = apiKey
        self.baseURL = baseURL
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

                    var usage: TokenUsage?
                    var hasToolCalls = false

                    for try await event in sse {
                        guard let data = event.data else { continue }

                        let json = try JSONDecoder().decode(JSONValue.self, from: Data(data.utf8))
                        guard case let .object(obj) = json else { continue }

                        // Handle API errors
                        if let errorObj = obj["error"]?.objectValue {
                            let code = errorObj["code"]?.stringValue
                                ?? errorObj["status"]?.stringValue
                                ?? "API_ERROR"
                            let msg = errorObj["message"]?.stringValue ?? "Gemini error"
                            let error = LLMError(code: code, message: msg)
                            continuation.yield(.finished(usage: usage, finishReason: .error(error)))
                            continue
                        }

                        // Parse usage metadata
                        if let meta = obj["usageMetadata"]?.objectValue {
                            let input = meta["promptTokenCount"]?.intValue ?? 0
                            let output = meta["candidatesTokenCount"]?.intValue ?? 0
                            usage = TokenUsage(promptTokens: input, completionTokens: output)
                        }

                        // Parse candidates
                        guard let candidates = obj["candidates"]?.arrayValue,
                              let firstCandidate = candidates.first?.objectValue else { continue }

                        let finishReasonStr = firstCandidate["finishReason"]?.stringValue

                        // Parse content parts
                        if let content = firstCandidate["content"]?.objectValue,
                           let parts = content["parts"]?.arrayValue {
                            for part in parts {
                                guard case let .object(partObj) = part else { continue }

                                // Thinking/reasoning text (Gemini marks with thought: true)
                                if partObj["thought"]?.boolValue == true,
                                   let text = partObj["text"]?.stringValue, !text.isEmpty {
                                    continuation.yield(.reasoningDelta(text))
                                    continue
                                }

                                // Regular text
                                if let text = partObj["text"]?.stringValue, !text.isEmpty {
                                    continuation.yield(.textDelta(text))
                                    continue
                                }

                                // Function call (Gemini sends complete, not streamed incrementally)
                                if let fc = partObj["functionCall"]?.objectValue {
                                    let name = fc["name"]?.stringValue ?? "tool"
                                    let args: String
                                    if let argsObj = fc["args"] {
                                        args = (try? argsObj.toJSONString()) ?? "{}"
                                    } else {
                                        args = "{}"
                                    }
                                    let callId = "call_\(UUID().uuidString)"
                                    hasToolCalls = true
                                    continuation.yield(.toolCallStart(id: callId, name: name))
                                    continuation.yield(.toolCallEnd(id: callId, name: name, arguments: args))
                                }
                            }
                        }

                        // Emit finished event on terminal finish reasons
                        if let reason = finishReasonStr, isTerminalReason(reason) {
                            let finishReason: FinishReason = switch reason {
                            case "MAX_TOKENS": .length
                            case "SAFETY", "RECITATION", "BLOCKLIST", "PROHIBITED_CONTENT":
                                .contentFilter
                            default: hasToolCalls ? .toolCalls : .stop
                            }
                            continuation.yield(.finished(usage: usage, finishReason: finishReason))
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

    private func isTerminalReason(_ reason: String) -> Bool {
        ["STOP", "MAX_TOKENS", "SAFETY", "RECITATION", "OTHER",
         "BLOCKLIST", "PROHIBITED_CONTENT"].contains(reason)
    }

    // MARK: - Request Building

    private func buildRequest(items: [ConversationItem], options: LLMRequestOptions) async throws -> URLRequest {
        var urlComponents = URLComponents(
            url: baseURL.appendingPathComponent("models/\(modelId):streamGenerateContent"),
            resolvingAgainstBaseURL: false
        )!
        urlComponents.queryItems = [
            URLQueryItem(name: "alt", value: "sse"),
            URLQueryItem(name: "key", value: apiKey)
        ]

        var req = URLRequest(url: urlComponents.url!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        var body: [String: JSONValue] = [:]

        // System instruction
        if let sys = options.systemPrompt {
            body["systemInstruction"] = .object([
                "parts": .array([.object(["text": .string(sys)])])
            ])
        }

        // Generation config
        var genConfig: [String: JSONValue] = [:]
        if let t = options.temperature {
            genConfig["temperature"] = .double(t)
        }
        if let m = options.maxOutputTokens {
            genConfig["maxOutputTokens"] = .int(m)
        }
        if !genConfig.isEmpty {
            body["generationConfig"] = .object(genConfig)
        }

        // Thinking config (reasoning effort)
        if let effort = options.reasoningEffort {
            switch effort {
            case .none:
                break
            case .low:
                body["thinkingConfig"] = .object(["thinkingBudget": .int(512)])
            case .medium:
                body["thinkingConfig"] = .object(["thinkingBudget": .int(2048)])
            case .high:
                body["thinkingConfig"] = .object(["thinkingBudget": .int(8192)])
            case .max:
                body["thinkingConfig"] = .object(["thinkingBudget": .int(32768)])
            }
        }

        // Tools
        if !options.tools.isEmpty {
            let declarations: [JSONValue] = options.tools.map { tool in
                var decl: [String: JSONValue] = [
                    "name": .string(tool.name),
                    "description": .string(tool.description)
                ]
                if case .object(let params) = tool.parameters, !params.isEmpty {
                    decl["parameters"] = tool.parameters
                }
                return .object(decl)
            }
            body["tools"] = .array([
                .object(["functionDeclarations": .array(declarations)])
            ])
        }

        // Contents (conversation history)
        let contents = try await encodeContents(items: items)
        body["contents"] = .array(contents)

        req.httpBody = try JSONEncoder().encode(JSONValue.object(body))
        return req
    }

    // MARK: - Content Encoding

    private func encodeContents(items: [ConversationItem]) async throws -> [JSONValue] {
        var contents: [[String: JSONValue]] = []
        var toolCallIdToName: [String: String] = [:]

        func appendToLastMessage(role: String, part: JSONValue) {
            if let last = contents.last, last["role"]?.stringValue == role {
                var msg = contents.removeLast()
                var parts = msg["parts"]?.arrayValue ?? []
                parts.append(part)
                msg["parts"] = .array(parts)
                contents.append(msg)
            } else {
                contents.append([
                    "role": .string(role),
                    "parts": .array([part])
                ])
            }
        }

        for item in items {
            switch item {
            case .message(let role, let content):
                let geminiRole = (role == .assistant) ? "model" : "user"
                let parts = try await encodeParts(from: content)
                if !parts.isEmpty {
                    contents.append([
                        "role": .string(geminiRole),
                        "parts": .array(parts)
                    ])
                }

            case .toolCall(let id, let name, let arguments):
                toolCallIdToName[id] = name
                let args: JSONValue = (try? JSONValue.parse(jsonString: arguments)) ?? .object([:])
                let part: JSONValue = .object([
                    "functionCall": .object([
                        "name": .string(name),
                        "args": args
                    ])
                ])
                appendToLastMessage(role: "model", part: part)

            case .toolResult(let id, let output):
                let name = toolCallIdToName[id] ?? "tool"
                let part: JSONValue = .object([
                    "functionResponse": .object([
                        "name": .string(name),
                        "response": .object([
                            "result": .string(output)
                        ])
                    ])
                ])
                appendToLastMessage(role: "user", part: part)
            }
        }

        return contents.map { .object($0) }
    }

    private func encodeParts(from contentParts: [ContentPart]) async throws -> [JSONValue] {
        var parts: [JSONValue] = []

        for part in contentParts {
            switch part {
            case .text(let text):
                parts.append(.object(["text": .string(text)]))

            case .image(let fileSource):
                let data = try await assetLoader.loadData(from: fileSource.url)
                let mt = fileSource.contentType.preferredMIMEType
                    ?? MediaTypeDetector.detect(from: data) ?? "image/jpeg"
                parts.append(.object([
                    "inlineData": .object([
                        "mimeType": .string(mt),
                        "data": .string(data.base64EncodedString())
                    ])
                ]))

            case .file(let fileSource):
                let data = try await assetLoader.loadData(from: fileSource.url)
                let mt = fileSource.contentType.preferredMIMEType ?? "application/octet-stream"
                parts.append(.object([
                    "inlineData": .object([
                        "mimeType": .string(mt),
                        "data": .string(data.base64EncodedString())
                    ])
                ]))
            }
        }

        return parts
    }
}
