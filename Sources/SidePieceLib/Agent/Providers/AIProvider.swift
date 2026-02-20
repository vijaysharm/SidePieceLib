//
//  AIProvider.swift
//  SidePiece
//
//  Protocol for LLM providers (OpenAI, Anthropic, etc.)
//

import Foundation

/// Protocol that all LLM providers must implement
public protocol AIProvider: Sendable {
    var id: String { get }
    var modelId: String { get }

    func stream(
        items: [ConversationItem],
        options: LLMRequestOptions
    ) -> AsyncThrowingStream<LLMStreamEvent, Error>
}

/// Shared HTTP functionality for providers
public actor HTTPStreamClient {
    private let session: URLSession
    private let hooks: StreamHooks

    public init(
        configuration: URLSessionConfiguration = .default,
        hooks: StreamHooks = .default
    ) {
        configuration.waitsForConnectivity = true
        self.session = URLSession(configuration: configuration)
        self.hooks = hooks
    }

    public func streamSSE(
        request: URLRequest,
    ) -> AsyncThrowingStream<SSEEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    // Hook: transform request before sending
                    let finalRequest = try await hooks.willSendRequest(request)

                    let (bytes, response) = try await session.bytes(for: finalRequest)

                    guard let http = response as? HTTPURLResponse else {
                        let error = LLMError(code: "INVALID_RESPONSE", message: "Expected HTTPURLResponse")
                        await hooks.didFail(error)
                        throw error
                    }

                    // Hook: inspect response headers
                    try await hooks.didReceiveResponse(http)

                    guard (200...299).contains(http.statusCode) else {
                        let body = try await collect(bytes: bytes)
                        let error = parseHTTPError(status: http.statusCode, body: body)
                        await hooks.didFail(error)
                        throw error
                    }

                    // Pass hooks to SSEParser
                    for try await event in SSEParser.parse(bytes, hooks: hooks) {
                        continuation.yield(event)
                    }

                    // Hook: stream completed successfully
                    await hooks.didComplete()
                    continuation.finish()
                } catch {
                    await hooks.didFail(error)
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    private func collect(bytes: URLSession.AsyncBytes) async throws -> Data {
        var data = Data()
        for try await b in bytes { data.append(b) }
        return data
    }

    private func parseHTTPError(status: Int, body: Data) -> LLMError {
        // Try decode {"error":{"message":...}}
        if let json = try? JSONDecoder().decode(JSONValue.self, from: body),
           case let .object(obj) = json,
           let err = obj["error"]?.objectValue,
           let msg = err["message"]?.stringValue {
            return LLMError(code: "HTTP_\(status)", message: msg)
        }

        let raw = String(decoding: body, as: UTF8.self)
        return LLMError(code: "HTTP_\(status)", message: "HTTP \(status)", underlying: raw.isEmpty ? nil : raw)
    }
}

/// Asset loader for handling images and files from URLs
public actor AssetLoader {
    private var cache: [URL: Data] = [:]

    public init() {}

    /// Load data from a URL (local file or remote)
    public func loadData(from url: URL) async throws -> Data {
        if let cached = cache[url] { return cached }
        let data: Data
        if url.isFileURL {
            data = try Data(contentsOf: url)
        } else {
            // For remote URLs, use URLSession
            let (fetchedData, _) = try await URLSession.shared.data(from: url)
            data = fetchedData
        }
        cache[url] = data
        return data
    }
}
