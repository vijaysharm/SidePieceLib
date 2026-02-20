//
//  MessageItemClient.swift
//  SidePiece
//

import Dependencies
import DependenciesMacros
import Foundation

@DependencyClient
public struct MessageItemClient: Sendable {
    var systemPrompt: @Sendable (PromptContext) async throws -> String?
}

public extension MessageItemClient {
    struct PromptContext: Sendable, Equatable {
        let model: Model
        let agent: Agent
        let projectURL: URL
    }
}

extension MessageItemClient: DependencyKey {
    public static let liveValue = MessageItemClient(
        systemPrompt: { context in
            guard context.agent == .defaultAsk else {
                return nil
            }
            return """
You are a helpful coding assistant. Answer the user's questions about their codebase. Use tools only when needed. Do NOT make changes.

Project root: \(context.projectURL.path)
"""
        }
    )
}

extension DependencyValues {
    public var messageItemClient: MessageItemClient {
        get { self[MessageItemClient.self] }
        set { self[MessageItemClient.self] = newValue }
    }
}
