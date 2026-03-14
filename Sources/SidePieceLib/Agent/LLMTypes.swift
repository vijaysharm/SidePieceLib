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
    public let cacheReadTokens: Int
    public let cacheWriteTokens: Int
    public var totalTokens: Int { promptTokens + completionTokens }
    public var details: [String: Int]

    public init(
        promptTokens: Int,
        completionTokens: Int,
        cacheReadTokens: Int = 0,
        cacheWriteTokens: Int = 0,
        details: [String: Int] = [:]
    ) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.cacheReadTokens = cacheReadTokens
        self.cacheWriteTokens = cacheWriteTokens
        self.details = details
    }
}

// MARK: - Cost Calculation

extension TokenUsage {
    /// Calculate the dollar cost of this usage given per-million-token rates.
    ///
    /// - Parameters:
    ///   - inputRate: Cost per million input tokens.
    ///   - outputRate: Cost per million output tokens.
    ///   - cacheReadRate: Cost per million cache-read tokens (typically cheaper than input).
    ///     Defaults to `nil`, which uses `inputRate * 0.1` (Anthropic's typical 90% discount).
    ///   - cacheWriteRate: Cost per million cache-write tokens (typically more expensive).
    ///     Defaults to `nil`, which uses `inputRate * 1.25` (Anthropic's typical 25% surcharge).
    /// - Returns: The estimated dollar cost.
    public func estimatedCost(
        inputRate: Decimal,
        outputRate: Decimal,
        cacheReadRate: Decimal? = nil,
        cacheWriteRate: Decimal? = nil
    ) -> Decimal {
        let million: Decimal = 1_000_000
        let inputCost = Decimal(promptTokens) * inputRate / million
        let outputCost = Decimal(completionTokens) * outputRate / million
        let readRate = cacheReadRate ?? (inputRate * Decimal(string: "0.1")!)
        let writeRate = cacheWriteRate ?? (inputRate * Decimal(string: "1.25")!)
        let cacheReadCost = Decimal(cacheReadTokens) * readRate / million
        let cacheWriteCost = Decimal(cacheWriteTokens) * writeRate / million
        return inputCost + outputCost + cacheReadCost + cacheWriteCost
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

// MARK: - Streaming Error

public enum StreamingError: LocalizedError, Equatable, Sendable {
    case llm(LLMError)
    case network(code: Int, domain: String, message: String)

    public init(from error: Error) {
        if let llmError = error as? LLMError {
            self = .llm(llmError)
        } else {
            let nsError = error as NSError
            self = .network(code: nsError.code, domain: nsError.domain, message: nsError.localizedDescription)
        }
    }

    public var errorDescription: String? {
        switch self {
        case let .llm(error):
            error.message
        case let .network(_, _, message):
            message
        }
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
    case max    // Maximum reasoning (Anthropic adaptive "max", OpenAI not supported)
}

// MARK: - Cache Retention

/// Controls prompt caching behavior for providers that support it.
/// Prompt caching can significantly reduce costs for multi-turn conversations.
public enum CacheRetention: String, Sendable, Equatable {
    /// No caching — every request is billed at full input token rate.
    case none
    /// Short-lived cache (typically 5 minutes). Good for interactive conversations.
    case short
    /// Long-lived cache (typically 1 hour). Good for batch workloads or slow conversations.
    case long
}

// MARK: - Service Tier

/// Controls the service tier for providers that support tiered pricing.
/// Currently relevant for OpenAI's flex/priority tiers.
public enum ServiceTier: String, Sendable, Equatable {
    /// Default tier — standard pricing and latency.
    case auto
    /// Flex tier — up to 50% cost reduction with potentially higher latency.
    case flex
    /// Priority tier — higher cost for lower latency and priority access.
    case priority
}

// MARK: - Request Options

public struct LLMRequestOptions: Sendable, Equatable {
    public let agent: Agent
    public var systemPrompt: String?
    public var temperature: Double?
    public var maxOutputTokens: Int?
    public var reasoningEffort: ReasoningEffort?
    public var tools: [ToolDefinition]
    public var cacheRetention: CacheRetention?
    public var serviceTier: ServiceTier?

    public init(
        agent: Agent,
        systemPrompt: String? = nil,
        temperature: Double? = nil,
        maxOutputTokens: Int? = nil,
        reasoningEffort: ReasoningEffort? = nil,
        tools: [ToolDefinition] = [],
        cacheRetention: CacheRetention? = nil,
        serviceTier: ServiceTier? = nil
    ) {
        self.agent = agent
        self.systemPrompt = systemPrompt
        self.temperature = temperature
        self.maxOutputTokens = maxOutputTokens
        self.reasoningEffort = reasoningEffort
        self.tools = tools
        self.cacheRetention = cacheRetention
        self.serviceTier = serviceTier
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

