//
//  LLMTypes.swift
//  SidePiece
//
//  Normalized types for multi-provider LLM streaming.
//

import Foundation
import UniformTypeIdentifiers

// MARK: - Content Parts

public enum ContentPart: Sendable, Equatable {
    case text(String)
    case image(FileSource)
    case file(FileSource)
}

public struct FileSource: Sendable, Equatable {
    let url: URL
    let contentType: UTType
}

// MARK: - Message Role

public enum MessageRole: String, Sendable, Codable, Equatable {
    case system
    case user
    case assistant
    case tool
}

// MARK: - Conversation Items

/// Items that represent the conversation history, normalized across providers.
public enum ConversationItem: Sendable, Equatable {
    case message(role: MessageRole, content: [ContentPart])
    case toolCall(id: String, name: String, arguments: String)
    case toolResult(id: String, output: String)
}

// MARK: - Token Usage

public struct TokenUsage: Sendable, Equatable, Codable {
    public static let zero = TokenUsage(promptTokens: 0, completionTokens: 0)

    public let promptTokens: Int
    public let completionTokens: Int
    public var totalTokens: Int { promptTokens + completionTokens }
    public var details: [String: Int]

    public init(promptTokens: Int, completionTokens: Int, details: [String: Int] = [:]) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.details = details
    }
}

// MARK: - Finish Reason

public enum FinishReason: Sendable, Equatable {
    case stop
    case length
    case toolCalls
    case contentFilter
    case error(LLMError)
    case unknown
}

// MARK: - LLM Errors

public struct LLMError: Error, Sendable, Equatable {
    public let code: String
    public let message: String
    public let underlying: String?

    public init(code: String, message: String, underlying: String? = nil) {
        self.code = code
        self.message = message
        self.underlying = underlying
    }
}

// MARK: - Stream Events

/// Provider-neutral streaming events for UI and orchestration.
public enum LLMStreamEvent: Sendable, Equatable {
    // Text streaming
    case textDelta(String)

    // Tool calls
    case toolCallStart(id: String, name: String)
    case toolCallDelta(id: String, args: String)
    case toolCallEnd(id: String, name: String, arguments: String)

    // Reasoning (optional; depends on model/provider/options)
    case reasoningDelta(String)

    // Lifecycle
    case finished(usage: TokenUsage?, finishReason: FinishReason)
}

// MARK: - Tool Definition

public struct ToolDefinition: Sendable, Hashable {
    public let name: String
    public let description: String
    public let parameters: JSONValue

    public init(name: String, description: String, parameters: JSONValue = .object([:])) {
        self.name = name
        self.description = description
        self.parameters = parameters
    }
}

// MARK: - Reasoning Effort

/// Controls how much reasoning/thinking a model performs before responding.
/// Maps to OpenAI's `reasoning.effort` and Anthropic's `thinking.budget_tokens`.
public enum ReasoningEffort: String, Sendable, Equatable {
    case none   // Disable reasoning entirely (OpenAI: "none", Anthropic: budget_tokens = 0)
    case low    // Minimal reasoning
    case medium // Moderate reasoning
    case high   // Full reasoning (default model behavior)
}

// MARK: - Request Options

public struct LLMRequestOptions: Sendable, Equatable {
    public let agent: Agent
    public var systemPrompt: String?
    public var temperature: Double?
    public var maxOutputTokens: Int?
    public var reasoningEffort: ReasoningEffort?
    public var tools: [ToolDefinition]

    public init(
        agent: Agent,
        systemPrompt: String? = nil,
        temperature: Double? = nil,
        maxOutputTokens: Int? = nil,
        reasoningEffort: ReasoningEffort? = nil,
        tools: [ToolDefinition] = []
    ) {
        self.agent = agent
        self.systemPrompt = systemPrompt
        self.temperature = temperature
        self.maxOutputTokens = maxOutputTokens
        self.reasoningEffort = reasoningEffort
        self.tools = tools
    }
}

// MARK: - Media Type Detection

public struct MediaTypeDetector {
    public static func detect(from data: Data) -> String? {
        // PNG
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "image/png" }
        // JPEG
        if data.starts(with: [0xFF, 0xD8, 0xFF]) { return "image/jpeg" }
        // GIF
        if data.starts(with: [0x47, 0x49, 0x46, 0x38]) { return "image/gif" }
        // WebP (RIFF....WEBP)
        if data.count >= 12 {
            let riff = data.prefix(4)
            let webp = data.subdata(in: 8..<12)
            if riff == Data([0x52, 0x49, 0x46, 0x46]) && webp == Data([0x57, 0x45, 0x42, 0x50]) {
                return "image/webp"
            }
        }
        // PDF: "%PDF"
        if data.starts(with: [0x25, 0x50, 0x44, 0x46]) { return "application/pdf" }

        return nil
    }

    public static func makeDataURL(mediaType: String, base64: String) -> String {
        "data:\(mediaType);base64,\(base64)"
    }
}

