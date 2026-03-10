//
//  Model.swift
//  SidePiece
//

import Foundation
import UniformTypeIdentifiers

public struct Model: Equatable, Sendable {
    public protocol ModelIdentifiable: Hashable, Sendable, CustomStringConvertible {}

    struct ModelIdentifier: ModelIdentifiable, @unchecked Sendable {
        let id: AnyHashable
        let description: String

        init<H>(_ base: H) where H : Hashable & Sendable & CustomStringConvertible {
            self.id = AnyHashable(base)
            self.description = base.description
        }
    }

    public enum Properties: Hashable, Sendable {
        public enum AttachmentType: Hashable, Sendable {
            case text
            case image([UTType])
            case pdf
            case other(String)
        }
        
        case displayName(String)
        case family(String)
        case provider(id: String, name: String)

        case attachment([AttachmentType])
        case reasoning
        case toolCall
        case temperature
        case imageGeneration
        case managedTools

        case preferred
        case archived

        case cost(input: Decimal, output: Decimal)
        case contextWindow(Int)
    }

    let id: ModelIdentifier
    let properties: Set<Model.Properties>

    private let name: String
    private let provider: (id: String, name: String)
    
    /// Handler that accepts conversation items and options, returns a stream of LLM events.
    /// Provider implementation is baked in at model creation time.
    let stream: @Sendable (
        _ items: [ConversationItem],
        _ options: LLMRequestOptions
    ) -> AsyncThrowingStream<LLMStreamEvent, Error>

    fileprivate init(
        id: ModelIdentifier,
        properties: Set<Model.Properties>,
        stream: @Sendable @escaping (
            _ items: [ConversationItem],
            _ options: LLMRequestOptions
        ) -> AsyncThrowingStream<LLMStreamEvent, Error>
    ) {
        self.id = id
        self.properties = properties
        self.stream = stream
        self.name = {
            for property in properties {
                if case .displayName(let displayName) = property {
                    return displayName
                }
            }
            return id.description
        }()
        self.provider = {
            for property in properties {
                if case let .provider(id, name) = property {
                    return (id: id, name: name)
                }
            }
            return (id: "unknown", name: "Unknown")
        }()
    }

    public static func == (lhs: Model, rhs: Model) -> Bool {
        lhs.id == rhs.id
    }

    public var modelId: String { id.description }

    public var displayName: String {
        name
    }
    
    var isPreferred: Bool { properties.contains(.preferred) }
    var isArchived: Bool { properties.contains(.archived) }
    var hasReasoning: Bool { properties.contains(.reasoning) }
    var hasToolCalling: Bool { properties.contains(.toolCall) }
    var hasManagedTools: Bool { properties.contains(.managedTools) }
    var hasImageGeneration: Bool { properties.contains(.imageGeneration) }
    var hasVision: Bool {
        for property in properties {
            if case let .attachment(attachments) = property {
                for attachment in attachments {
                    if case .image = attachment {
                        return true
                    }
                }
            }
        }
        return false
    }
    var hasPDFSupport: Bool {
        for property in properties {
            if case let .attachment(attachments) = property {
                for attachment in attachments {
                    if case .pdf = attachment {
                        return true
                    }
                }
            }
        }
        return false
    }
    var supportsTemperature: Bool {
        for property in properties {
            if case .temperature = property {
                return true
            }
        }
        return false
    }

    var isFast: Bool {
        let fastIndicators = ["mini", "flash", "instant", "haiku", "small"]
        return fastIndicators.contains { name.lowercased().contains($0) }
    }
    
    public var providerId: String {
        provider.id
    }

    public var providerName: String {
        provider.name
    }
    
    var family: String? {
        for property in properties {
            if case let .family(name) = property {
                return name
            }
        }
        return nil
    }

    var cost: (input: Decimal, output: Decimal)? {
        for property in properties {
            if case let .cost(input, output) = property {
                return (input: input, output: output)
            }
        }
        return nil
    }

    var contextWindow: Int? {
        for property in properties {
            if case let .contextWindow(ctx) = property {
                return ctx
            }
        }
        return nil
    }

    var descriptionText: String {
        family ?? provider.name
    }
}

// MARK: - Factory Methods

public extension Model {
    /// Create a model with a custom stream
    static func model(
        id: any Model.ModelIdentifiable,
        properties: Set<Model.Properties>,
        stream: @escaping @Sendable (
            _ items: [ConversationItem],
            _ options: LLMRequestOptions
        ) -> AsyncThrowingStream<LLMStreamEvent, Error>
    ) -> Model {
        Model(id: .init(id), properties: properties, stream: stream)
    }
    
    static func model(
        _ model: ModelRegistry.Model,
        provider: ModelRegistry.Provider,
        properties: Set<Model.Properties> = [],
        stream: @escaping @Sendable (
            _ items: [ConversationItem],
            _ options: LLMRequestOptions
        ) -> AsyncThrowingStream<LLMStreamEvent, Error>
    ) -> Self {
        var modelProperties: Set<Model.Properties> = []
        modelProperties.insert(.displayName(model.name))
        if let family = model.family {
            modelProperties.insert(.family(family.rawValue))
        }

        if model.reasoning {
            modelProperties.insert(.reasoning)
        }
        if model.toolCall {
            modelProperties.insert(.toolCall)
        }
        
        var attachments: [Properties.AttachmentType] = [.text]
        if model.modalities.input.contains(.image) {
            attachments.append(.image([.jpeg, .png]))
        }
        if model.modalities.input.contains(.pdf) {
            attachments.append(.pdf)
        }
        modelProperties.insert(.attachment(attachments))
        
        if model.modalities.output.contains(.image) {
            modelProperties.insert(.imageGeneration)
        }
        
        if let temperature = model.temperature, temperature {
            modelProperties.insert(.temperature)
        }
        
        modelProperties.insert(.provider(id: provider.id.rawValue, name: provider.name))

        if let cost = model.cost {
            modelProperties.insert(.cost(input: cost.input, output: cost.output))
        }
        modelProperties.insert(.contextWindow(model.limit.context))

        // We do a union on modelProperties because when we iterate to look for properties
        // we want the ones from properties to be found first.
        return Model(
            id: .init("\(provider.id.rawValue)/\(model.id.rawValue)"),
            properties: properties.union(modelProperties),
            stream: stream
        )
    }

    /// Create an OpenAI-compatible model (works with OpenAI API and OpenRouter)
    static func openAI(
        id: String,
        modelId: String,
        apiKey: String,
        baseURL: URL = URL(string: "https://api.openai.com/v1")!,
        properties: Set<Model.Properties> = []
    ) -> Model {
        Model(
            id: .init(id),
            properties: properties,
            stream: { items, options in
                OpenAIProvider(
                    modelId: modelId,
                    apiKey: apiKey,
                    baseURL: baseURL
                ).stream(items: items, options: options)
            }
        )
    }

    /// Create an Anthropic model
    static func anthropic(
        id: String,
        modelId: String,
        apiKey: String,
        baseURL: URL = URL(string: "https://api.anthropic.com")!,
        properties: Set<Model.Properties> = []
    ) -> Model {
        Model(
            id: .init(id),
            properties: properties,
            stream: { items, options in
                AnthropicProvider(
                    modelId: modelId,
                    apiKey: apiKey,
                    baseURL: baseURL
                ).stream(items: items, options: options)
            }
        )
    }

    /// Create a Google Gemini model
    static func gemini(
        id: String,
        modelId: String,
        apiKey: String,
        baseURL: URL = URL(string: "https://generativelanguage.googleapis.com/v1beta")!,
        properties: Set<Model.Properties> = []
    ) -> Model {
        Model(
            id: .init(id),
            properties: properties,
            stream: { items, options in
                GeminiProvider(
                    modelId: modelId,
                    apiKey: apiKey,
                    baseURL: baseURL
                ).stream(items: items, options: options)
            }
        )
    }

    /// Create a Claude Code model (CLI-based, subprocess streaming)
    static func claudeCode(
        id: String,
        modelId: String = "sonnet",
        executablePath: String = "claude",
        dangerouslySkipPermissions: Bool = true,
        properties: Set<Model.Properties> = []
    ) -> Model {
        let sessionStore = ClaudeCodeSessionStore()
        var allProperties = properties
        allProperties.insert(.managedTools)
        allProperties.insert(.toolCall)
        return Model(
            id: .init(id),
            properties: allProperties,
            stream: { items, options in
                ClaudeCodeProvider(
                    modelId: modelId,
                    executablePath: executablePath,
                    sessionStore: sessionStore,
                    dangerouslySkipPermissions: dangerouslySkipPermissions
                ).stream(items: items, options: options)
            }
        )
    }

    /// Create a Codex model (CLI-based, JSON-RPC subprocess)
    static func codex(
        id: String,
        modelId: String = "codex",
        apiKey: String? = nil,
        executablePath: String = "codex",
        properties: Set<Model.Properties> = []
    ) -> Model {
        var allProperties = properties
        allProperties.insert(.managedTools)
        allProperties.insert(.toolCall)
        return Model(
            id: .init(id),
            properties: allProperties,
            stream: { items, options in
                CodexProvider(
                    modelId: modelId,
                    apiKey: apiKey,
                    executablePath: executablePath
                ).stream(items: items, options: options)
            }
        )
    }

    /// Create a mock model for testing/preview (streams demo content)
    static func mock(
        id: String = "mock",
        name: String = "mock"
    ) -> Model {
        Model(
            id: .init(id),
            properties: [.displayName(name)],
            stream: { _, _ in
                AsyncThrowingStream { continuation in
                        let demoMarkdown: String = """
                        # Welcome to SidePiece Markdown Demo

                        This is a **demo** of markdown features.

                        ## Features

                        - **Bold** and _italic_ text
                        - Inline code: `let x = 42`
                        - Code blocks:
                        ```swift
                        struct Example {
                            let message = "Hello, world!"
                        }
                        ```
                        - Blockquotes:
                          > "Markdown makes documentation easy!"
                          > – A wise developer

                        - Links: [Apple Developer](https://developer.apple.com)
                        - Images:
                        ![Swift Logo](https://swift.org/assets/images/swift.svg)

                        ## Table Example

                        | Syntax      | Description |
                        | ----------- | ----------- |
                        | Header      | Title       |
                        | Paragraph   | Text        |

                        ## Tasks

                        - [x] Write demo markdown
                        - [ ] Add more examples

                        ## Nested Lists

                        1. First item
                            - Sub-item 1
                            - Sub-item 2
                        2. Second item

                        ## Horizontal Rule

                        ---

                        ### Emojis

                        :rocket: :sparkles: :apple:

                        ### Escaped Characters


                        ### Footnote

                        Here's a reference[^1].

                        [^1]: This is the footnote.

                        ## End

                        Thanks for trying out the markdown demo!

                        """
                    let task = Task {
                        defer { continuation.finish() }
                        var offset = demoMarkdown.startIndex
                        while !Task.isCancelled {
                            try? await Task.sleep(for: .milliseconds(50))
                            // When we reach the end, wrap around to the beginning
                            if offset >= demoMarkdown.endIndex {
                                offset = demoMarkdown.startIndex
                            }
                            // Choose a random chunk size, up to remaining length
                            let maxChunk = 10
                            let minChunk = 2
                            let remaining = demoMarkdown.distance(from: offset, to: demoMarkdown.endIndex)
                            let chunkLen = min(Int.random(in: minChunk...maxChunk), remaining)
                            let chunkEnd = demoMarkdown.index(offset, offsetBy: chunkLen, limitedBy: demoMarkdown.endIndex) ?? demoMarkdown.endIndex
                            let chunk = String(demoMarkdown[offset..<chunkEnd])
                            offset = chunkEnd
                            continuation.yield(.textDelta(chunk))
                        }
                        continuation.yield(.finished(usage: nil, finishReason: .stop))
                    }
                    continuation.onTermination = { _ in task.cancel() }
                }
            }
        )
    }

    /// Create a model that never produces output (useful for placeholder/selection states)
    static func never(
        id: String,
        properties: Set<Model.Properties> = []
    ) -> Model {
        Model(
            id: .init(id),
            properties: properties,
            stream: { _, _ in
                AsyncThrowingStream { _ in }
            }
        )
    }
}

extension String: Model.ModelIdentifiable {}
