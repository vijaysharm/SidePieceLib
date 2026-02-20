//
//  StreamHooks.swift
//  SidePiece
//
//  Composable hooks for intercepting the streaming request/response lifecycle.
//

import Foundation

/// Composable hooks for intercepting the streaming request/response lifecycle.
/// All hooks have defaults that pass through data unchanged.
public struct StreamHooks: Sendable {

    /// Called after request is built, before sending.
    /// Return the request (possibly modified) or throw to cancel.
    public var willSendRequest: @Sendable (URLRequest) async throws -> URLRequest

    /// Called when HTTP response headers are received.
    /// Throw to abort the stream (e.g., on unexpected status).
    public var didReceiveResponse: @Sendable (HTTPURLResponse) async throws -> Void

    /// Called for each raw SSE line before parsing.
    /// Return the line (possibly modified) for downstream processing.
    public var didReceiveSSELine: @Sendable (String) async -> String

    /// Called when stream completes successfully.
    public var didComplete: @Sendable () async -> Void

    /// Called when an error occurs at any phase.
    public var didFail: @Sendable (Error) async -> Void

    public init(
        willSendRequest: @escaping @Sendable (URLRequest) async throws -> URLRequest = { $0 },
        didReceiveResponse: @escaping @Sendable (HTTPURLResponse) async throws -> Void = { _ in },
        didReceiveSSELine: @escaping @Sendable (String) async -> String = { $0 },
        didComplete: @escaping @Sendable () async -> Void = {},
        didFail: @escaping @Sendable (Error) async -> Void = { _ in }
    ) {
        self.willSendRequest = willSendRequest
        self.didReceiveResponse = didReceiveResponse
        self.didReceiveSSELine = didReceiveSSELine
        self.didComplete = didComplete
        self.didFail = didFail
    }

    /// Default pass-through hooks
    public static let `default` = StreamHooks()
}

// MARK: - Composition

extension StreamHooks {
    /// Combine two hooks - both are called, transforms applied in sequence
    public func combined(with other: StreamHooks) -> StreamHooks {
        StreamHooks(
            willSendRequest: { request in
                let r1 = try await self.willSendRequest(request)
                return try await other.willSendRequest(r1)
            },
            didReceiveResponse: { response in
                try await self.didReceiveResponse(response)
                try await other.didReceiveResponse(response)
            },
            didReceiveSSELine: { line in
                let l1 = await self.didReceiveSSELine(line)
                return await other.didReceiveSSELine(l1)
            },
            didComplete: {
                await self.didComplete()
                await other.didComplete()
            },
            didFail: { error in
                await self.didFail(error)
                await other.didFail(error)
            }
        )
    }
}
