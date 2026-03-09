//
//  CodexProvider.swift
//  SidePiece
//
//  AIProvider implementation wrapping `codex app-server` with JSON-RPC
//  bidirectional communication over stdin/stdout.
//

import Dependencies
import Foundation

// MARK: - Error

public enum CodexError: LocalizedError, Equatable, Sendable {
    case jsonRPCError(code: Int, message: String)
    case sessionStartFailed(String)
    case processFailed(ProcessStreamError)
    case noPromptFound
    case encodingFailed(String)

    public var errorDescription: String? {
        switch self {
        case .jsonRPCError(let code, let message):
            "Codex JSON-RPC error (\(code)): \(message)"
        case .sessionStartFailed(let detail):
            "Failed to start Codex session: \(detail)"
        case .processFailed(let error):
            "Codex process error: \(error.localizedDescription)"
        case .noPromptFound:
            "No user message found to send to Codex"
        case .encodingFailed(let detail):
            "Failed to encode JSON-RPC message: \(detail)"
        }
    }
}

// MARK: - JSON-RPC Helpers

private struct JSONRPCRequest {
    let id: Int
    let method: String
    let params: JSONValue

    func toJSONValue() -> JSONValue {
        .object([
            "jsonrpc": .string("2.0"),
            "id": .int(id),
            "method": .string(method),
            "params": params
        ])
    }
}

private enum JSONRPCMessageKind {
    case response(id: Int)
    case notification(method: String)
    case serverRequest(id: JSONValue, method: String)
}

private func classify(_ obj: [String: JSONValue]) -> JSONRPCMessageKind? {
    let hasMethod = obj["method"]?.stringValue
    let hasId = obj["id"]

    switch (hasId, hasMethod) {
    case (let id?, let method?) where id != .null:
        // Server request: has both id and method
        return .serverRequest(id: id, method: method)
    case (let id?, nil):
        // Response: has id but no method
        if let intId = id.intValue {
            return .response(id: intId)
        }
        return nil
    case (_, let method?):
        // Notification: has method but no id (or null id)
        return .notification(method: method)
    default:
        return nil
    }
}

// MARK: - Provider

public struct CodexProvider: AIProvider, Sendable {
    public let id: String = "codex"
    public let modelId: String
    let apiKey: String
    let executablePath: String

    public init(
        modelId: String,
        apiKey: String,
        executablePath: String = "codex"
    ) {
        self.modelId = modelId
        self.apiKey = apiKey
        self.executablePath = executablePath
    }

    public func stream(
        items: [ConversationItem],
        options: LLMRequestOptions
    ) -> AsyncThrowingStream<LLMStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let prompt = extractPrompt(from: items) else {
                        let error = LLMError(code: "NO_PROMPT", message: "No user message found")
                        continuation.yield(.finished(usage: nil, finishReason: .error(error)))
                        continuation.finish()
                        return
                    }

                    let configuration = ProcessConfiguration(
                        executablePath: executablePath,
                        arguments: ["app-server", "--api-key", apiKey]
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

                    var requestId = 0
                    func nextId() -> Int {
                        requestId += 1
                        return requestId
                    }

                    func sendRequest(method: String, params: JSONValue) async throws {
                        let request = JSONRPCRequest(id: nextId(), method: method, params: params)
                        let jsonString = try request.toJSONValue().toJSONString()
                        try await handle.writeLine(jsonString)
                    }

                    func sendResponse(id: JSONValue, result: JSONValue) async throws {
                        let response: JSONValue = .object([
                            "jsonrpc": .string("2.0"),
                            "id": id,
                            "result": result
                        ])
                        let jsonString = try response.toJSONString()
                        try await handle.writeLine(jsonString)
                    }

                    // Send session.start
                    var sessionParams: [String: JSONValue] = [
                        "model": .string(modelId)
                    ]
                    if let systemPrompt = options.systemPrompt {
                        sessionParams["instructions"] = .string(systemPrompt)
                    }
                    try await sendRequest(method: "session.start", params: .object(sessionParams))

                    // Send turn.start with the prompt
                    try await sendRequest(
                        method: "turn.start",
                        params: .object(["prompt": .string(prompt)])
                    )

                    // Parse stdout events
                    let events = NDJSONParser.parse(handle.stdout)
                    var usage: TokenUsage?

                    for try await json in events {
                        guard case let .object(obj) = json else { continue }
                        guard let kind = classify(obj) else { continue }

                        switch kind {
                        case .response:
                            // Response to our request — check for errors
                            if let errorObj = obj["error"]?.objectValue {
                                let code = errorObj["code"]?.intValue ?? -1
                                let msg = errorObj["message"]?.stringValue ?? "Unknown error"
                                let llmError = LLMError(
                                    code: "JSONRPC_\(code)",
                                    message: msg
                                )
                                continuation.yield(.finished(usage: usage, finishReason: .error(llmError)))
                            }

                        case .notification(let method):
                            let params = obj["params"]?.objectValue ?? [:]
                            try await handleNotification(
                                method: method,
                                params: params,
                                continuation: continuation,
                                usage: &usage
                            )

                        case .serverRequest(let id, let method):
                            // Auto-approve tool calls (v1 behavior)
                            if method == "item.requestApproval" {
                                let params = obj["params"]?.objectValue ?? [:]
                                let toolName = params["tool_name"]?.stringValue ?? "tool"
                                let toolArgs = params["arguments"]?.objectValue
                                let toolId = params["id"]?.stringValue ?? "call_\(UUID().uuidString)"

                                // Surface tool info in UI
                                continuation.yield(.toolCallStart(id: toolId, name: toolName))
                                if let args = toolArgs {
                                    let argsString = (try? JSONValue.object(args).toJSONString()) ?? "{}"
                                    continuation.yield(.toolCallEnd(
                                        id: toolId,
                                        name: toolName,
                                        arguments: argsString
                                    ))
                                } else {
                                    continuation.yield(.toolCallEnd(
                                        id: toolId,
                                        name: toolName,
                                        arguments: "{}"
                                    ))
                                }

                                // Send approval response
                                try await sendResponse(
                                    id: id,
                                    result: .object(["approved": .bool(true)])
                                )
                            } else {
                                // Unknown server request — respond with empty result
                                try await sendResponse(id: id, result: .object([:]))
                            }
                        }
                    }

                    // If we haven't sent a finished event yet, send one now
                    continuation.yield(.finished(usage: usage, finishReason: .stop))
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

    // MARK: - Notification Handling

    private func handleNotification(
        method: String,
        params: [String: JSONValue],
        continuation: AsyncThrowingStream<LLMStreamEvent, Error>.Continuation,
        usage: inout TokenUsage?
    ) async throws {
        switch method {
        case "item.content.delta":
            let text = params["text"]?.stringValue ?? params["delta"]?.stringValue ?? ""
            if !text.isEmpty {
                continuation.yield(.textDelta(text))
            }

        case "item.functionCall.added":
            let toolId = params["id"]?.stringValue ?? "call_\(UUID().uuidString)"
            let name = params["name"]?.stringValue ?? "tool"
            continuation.yield(.toolCallStart(id: toolId, name: name))

        case "item.functionCall.arguments.delta":
            let toolId = params["id"]?.stringValue ?? ""
            let args = params["delta"]?.stringValue ?? ""
            if !toolId.isEmpty, !args.isEmpty {
                continuation.yield(.toolCallDelta(id: toolId, args: args))
            }

        case "item.functionCall.done":
            let toolId = params["id"]?.stringValue ?? ""
            let name = params["name"]?.stringValue ?? "tool"
            let args = params["arguments"]?.stringValue ?? "{}"
            continuation.yield(.toolCallEnd(id: toolId, name: name, arguments: args))

        case "turn.completed":
            if let u = params["usage"]?.objectValue {
                let input = u["input_tokens"]?.intValue ?? u["prompt_tokens"]?.intValue ?? 0
                let output = u["output_tokens"]?.intValue ?? u["completion_tokens"]?.intValue ?? 0
                usage = TokenUsage(promptTokens: input, completionTokens: output)
            }
            continuation.yield(.finished(usage: usage, finishReason: .stop))

        default:
            break
        }
    }

    // MARK: - Helpers

    private func extractPrompt(from items: [ConversationItem]) -> String? {
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
