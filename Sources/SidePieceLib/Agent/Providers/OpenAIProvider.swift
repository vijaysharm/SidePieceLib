//
//  OpenAIProvider.swift
//  SidePiece
//
//  OpenAI Responses API provider implementation.
//

import Foundation
import UniformTypeIdentifiers

/// OpenAI-compatible provider using the Responses API
public struct OpenAIProvider: AIProvider, Sendable {
    public let id: String = "openai"
    public let modelId: String
    public let apiKey: String
    public let baseURL: URL

    private let http: HTTPStreamClient
    private let assetLoader: AssetLoader
    private let hooks: StreamHooks

    public init(
        modelId: String,
        apiKey: String,
        baseURL: URL = URL(string: "https://api.openai.com/v1")!,
        hooks: StreamHooks = .default
    ) {
        self.modelId = modelId
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.http = HTTPStreamClient()
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

                    var toolCallArgs: [String: String] = [:]
                    var toolCallNames: [String: String] = [:]
                    var itemIdToCallId: [String: String] = [:]

                    for try await event in sse {
//                        print("*** \(event)")
                        guard let data = event.data else { continue }

                        if data == "[DONE]" {
                            let finishReason: FinishReason = toolCallNames.isEmpty ? .stop : .toolCalls
                            continuation.yield(.finished(usage: nil, finishReason: finishReason))
                            continuation.finish()
                            return
                        }

                        let json = try JSONDecoder().decode(JSONValue.self, from: Data(data.utf8))
                        guard case let .object(obj) = json else { continue }

                        // Handle API errors
                        if let errObj = obj["error"]?.objectValue, let msg = errObj["message"]?.stringValue {
                            continuation.yield(.finished(usage: nil, finishReason: .error(LLMError(code: "API_ERROR", message: msg))))
                            continue
                        }

                        guard let type = obj["type"]?.stringValue else { continue }

                        switch type {
                        case "response.output_text.delta":
                            let delta = obj["delta"]?.stringValue ?? ""
                            if !delta.isEmpty {
                                continuation.yield(.textDelta(delta))
                            }

                        case "response.content_part.delta":
                            // OpenRouter often emits this
                            let delta = obj["delta"]?.stringValue ?? ""
                            if !delta.isEmpty {
                                continuation.yield(.textDelta(delta))
                            }

                        case "response.function_call_arguments.delta":
                            let itemId = obj["item_id"]?.stringValue
                            let callId = obj["call_id"]?.stringValue ?? itemId.flatMap({ itemIdToCallId[$0] }) ?? "unknown"
                            let delta = obj["delta"]?.stringValue ?? ""
                            if !delta.isEmpty {
                                toolCallArgs[callId, default: ""] += delta
                                continuation.yield(.toolCallDelta(id: callId, args: delta))
                            }

                        case "response.output_item.added":
                            if let item = obj["item"]?.objectValue,
                               let itemType = item["type"]?.stringValue {
                                if itemType == "function_call" {
                                    let callId = item["call_id"]?.stringValue ?? "call_\(UUID().uuidString)"
                                    let itemId = item["id"]?.stringValue
                                    let name = item["name"]?.stringValue ?? "tool"
                                    toolCallNames[callId] = name
                                    toolCallArgs[callId] = ""
                                    if let itemId { itemIdToCallId[itemId] = callId }
                                    continuation.yield(.toolCallStart(id: callId, name: name))
                                }
                            }

                        case "response.function_call_arguments.done":
                            let itemId = obj["item_id"]?.stringValue
                            let callId = obj["call_id"]?.stringValue ?? itemId.flatMap({ itemIdToCallId[$0] }) ?? "unknown"
                            let args = obj["arguments"]?.stringValue ?? toolCallArgs[callId] ?? "{}"
                            let name = toolCallNames[callId] ?? "tool"
                            continuation.yield(.toolCallEnd(id: callId, name: name, arguments: args))

                        case "response.reasoning_summary_text.delta",
                             "response.reasoning_text.delta":
                            let delta = obj["delta"]?.stringValue ?? ""
                            if !delta.isEmpty {
                                continuation.yield(.reasoningDelta(delta))
                            }

                        case "response.output_item.done":
                            // Completed output item — only handle function_call as a
                            // fallback for tool call completion. Text was already
                            // streamed via response.output_text.delta events.
                            if let item = obj["item"]?.objectValue,
                               let itemType = item["type"]?.stringValue,
                               itemType == "function_call" {
                                let callId = item["call_id"]?.stringValue ?? "unknown"
                                let args = item["arguments"]?.stringValue ?? toolCallArgs[callId] ?? "{}"
                                let name = item["name"]?.stringValue ?? toolCallNames[callId] ?? "tool"
                                continuation.yield(.toolCallEnd(id: callId, name: name, arguments: args))
                            }

                        case "response.created",
                             "response.in_progress",
                             "response.content_part.added",
                             "response.output_text.done",
                             "response.content_part.done",
                             "response.reasoning_text.done",
                             "response.reasoning_summary_text.done":
                            // Structural/lifecycle & summary events — safe to ignore.
                            // output_text.done and content_part.done are summaries of
                            // text already streamed via output_text.delta events.
                            break

                        case "response.completed", "response.done":
                            let usage = parseUsage(from: obj)
                            let finishReason: FinishReason = toolCallNames.isEmpty ? .stop : .toolCalls
                            continuation.yield(.finished(usage: usage, finishReason: finishReason))

                        case "response.incomplete":
                            let usage = parseUsage(from: obj)
                            continuation.yield(.finished(usage: usage, finishReason: .length))

                        case "response.failed":
                            let usage = parseUsage(from: obj)
                            
                            // Extract error details from response.error
                            if let response = obj["response"]?.objectValue,
                               let errorObj = response["error"]?.objectValue {
                                let code = errorObj["code"]?.stringValue ?? "RESPONSE_FAILED"
                                let message = errorObj["message"]?.stringValue ?? "Response failed"
                                continuation.yield(.finished(usage: usage, finishReason: .error(LLMError(code: code, message: message))))
                            } else {
                                continuation.yield(.finished(usage: usage, finishReason: .error(LLMError(code: "RESPONSE_FAILED", message: "Response failed: no message provided"))))
                            }
                        default:
                            print("[OpenAIProvider] unhandled SSE event type: \(type), data: \(data.prefix(500))")
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
        let url = baseURL.appendingPathComponent("responses")

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        var body: [String: JSONValue] = [
            "model": .string(modelId),
            "stream": .bool(true),
            "store": .bool(false)
        ]

        if let sys = options.systemPrompt {
            body["instructions"] = .string(sys)
        }
        if let t = options.temperature {
            body["temperature"] = .double(t)
        }
        if let m = options.maxOutputTokens {
            body["max_output_tokens"] = .int(m)
        }

        // Reasoning effort
        if let effort = options.reasoningEffort {
            body["reasoning"] = .object([
                "effort": .string(effort.rawValue)
            ])
        }

        // Tools
        if !options.tools.isEmpty {
            body["tools"] = .array(options.tools.map { tool in
                .object([
                    "type": .string("function"),
                    "name": .string(tool.name),
                    "description": .string(tool.description),
                    "parameters": tool.parameters
                ])
            })
        }

        // Input items
        let encodedInput = try await encodeInputItems(items)
        body["input"] = .array(encodedInput)

        let data = try JSONEncoder().encode(JSONValue.object(body))
        req.httpBody = data
        return req
    }

    private func encodeInputItems(_ items: [ConversationItem]) async throws -> [JSONValue] {
        var result: [JSONValue] = []

        for item in items {
            switch item {
            case .message(let role, let content):
                let encodedContent = try await encodeContent(content, role: role)
                result.append(.object([
                    "type": .string("message"),
                    "role": .string(role.rawValue),
                    "content": .array(encodedContent)
                ]))

            case .toolCall(let id, let name, let arguments):
                result.append(.object([
                    "type": .string("function_call"),
                    "id": .string("fc_\(UUID().uuidString)"),
                    "call_id": .string(id),
                    "name": .string(name),
                    "arguments": .string(arguments)
                ]))

            case .toolResult(let id, let output):
                result.append(.object([
                    "type": .string("function_call_output"),
                    "id": .string("fco_\(UUID().uuidString)"),
                    "call_id": .string(id),
                    "output": .string(output)
                ]))
            }
        }

        return result
    }

    private func encodeContent(_ parts: [ContentPart], role: MessageRole) async throws -> [JSONValue] {
        var result: [JSONValue] = []

        for part in parts {
            switch part {
            case .text(let text):
                let type = (role == .assistant) ? "output_text" : "input_text"
                result.append(.object([
                    "type": .string(type),
                    "text": .string(text)
                ]))

            case .image(let fileSource):
                let urlString = try await encodeImageURL(fileSource)
                result.append(.object([
                    "type": .string("input_image"),
                    "image_url": .string(urlString)
                ]))

            case .file(let fileSource):
                // For files, we embed as text for now (could implement file upload later)
                let data = try await assetLoader.loadData(from: fileSource.url)
                let text = String(decoding: data, as: UTF8.self)
                result.append(.object([
                    "type": .string("input_text"),
                    "text": .string("[File: \(fileSource.url.lastPathComponent)]\n\(text)")
                ]))
            }
        }

        return result
    }

    private func encodeImageURL(_ fileSource: FileSource) async throws -> String {
        let url = fileSource.url

        // If remote https, pass through
        if url.scheme == "https" {
            return url.absoluteString
        }

        // Otherwise load and embed as data URL
        let data = try await assetLoader.loadData(from: url)
        let media = fileSource.contentType.preferredMIMEType ?? MediaTypeDetector.detect(from: data) ?? "image/jpeg"
        let base64 = data.base64EncodedString()
        return MediaTypeDetector.makeDataURL(mediaType: media, base64: base64)
    }

    private func parseUsage(from obj: [String: JSONValue]) -> TokenUsage? {
        if let response = obj["response"]?.objectValue,
           let usage = response["usage"]?.objectValue {
            let input = usage["input_tokens"]?.intValue ?? 0
            let output = usage["output_tokens"]?.intValue ?? 0
            return TokenUsage(promptTokens: input, completionTokens: output)
        }
        return nil
    }
}
