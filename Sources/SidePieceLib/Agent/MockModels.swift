//
//  MockModels.swift
//  SidePiece
//
//  Mock models for testing and previewing the SidePiece app.
//

import Foundation

// MARK: - Mock Namespace & Helpers

public enum Mock {
    static let textDelay: Duration = .milliseconds(50)
    static let toolDelay: Duration = .milliseconds(100)

    /// Chunk text into random-sized pieces for realistic streaming simulation
    static func chunk(_ text: String, minSize: Int = 2, maxSize: Int = 10) -> [String] {
        var chunks: [String] = []
        var offset = text.startIndex
        while offset < text.endIndex {
            let remaining = text.distance(from: offset, to: text.endIndex)
            let chunkLen = min(Int.random(in: minSize...maxSize), remaining)
            let chunkEnd = text.index(offset, offsetBy: chunkLen, limitedBy: text.endIndex) ?? text.endIndex
            chunks.append(String(text[offset..<chunkEnd]))
            offset = chunkEnd
        }
        return chunks
    }

    /// Check if conversation has tool results (used to determine state in tool mocks)
    static func hasToolResult(in items: [ConversationItem]) -> Bool {
        items.contains { item in
            if case .toolResult = item { return true }
            return false
        }
    }

    /// Count tool results in conversation
    static func toolResultCount(in items: [ConversationItem]) -> Int {
        items.filter { item in
            if case .toolResult = item { return true }
            return false
        }.count
    }
}

// MARK: - Text Responses

extension Mock {
    /// Basic markdown response with common formatting
    public static let text_simple = Model.model(
        id: "mock.text_simple",
        properties: [
            .displayName("Mock: Simple Text"),
            .preferred
        ]
    ) { _, _ in
        AsyncThrowingStream { continuation in
            let task = Task {
                let markdown = """
                # Hello!

                This is a **simple** response with basic markdown.

                ## Features demonstrated:
                - Bold and _italic_ text
                - Inline `code` formatting
                - A code block:

                ```swift
                let greeting = "Hello, world!"
                print(greeting)
                ```

                > A thoughtful quote to end with.

                Thanks for testing!
                """

                for chunk in Mock.chunk(markdown) {
                    guard !Task.isCancelled else { break }
                    try? await Task.sleep(for: Mock.textDelay)
                    continuation.yield(.textDelta(chunk))
                }

                continuation.yield(.finished(
                    usage: TokenUsage(promptTokens: 50, completionTokens: 80),
                    finishReason: .stop
                ))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Long response with 10+ sections for scroll testing
    public static let text_long = Model.model(
        id: "mock.text_long",
        properties: [
            .displayName("Mock: Long Text"),
            .preferred
        ]
    ) { _, _ in
        AsyncThrowingStream { continuation in
            let task = Task {
                let sections = (1...12).map { i in
                    """

                    ## Section \(i): Lorem Ipsum

                    Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris.

                    ### Key Points for Section \(i)
                    - Point A: Duis aute irure dolor in reprehenderit
                    - Point B: Excepteur sint occaecat cupidatat non proident
                    - Point C: Sunt in culpa qui officia deserunt mollit

                    ```python
                    def section_\(i)():
                        \"\"\"Example code for section \(i)\"\"\"
                        return "processing..."
                    ```

                    > Important note for section \(i): This is a blockquote that spans
                    > multiple lines to test the rendering of longer quotes.

                    """
                }.joined()

                let markdown = """
                # Comprehensive Documentation Test

                This is a **long document** designed to test scrolling behavior and rendering performance.

                \(sections)

                ---

                ## Conclusion

                This concludes our extensive documentation test. The document contains:
                - 12 major sections
                - Multiple code blocks
                - Various markdown elements
                - Nested lists and blockquotes

                | Section | Status |
                |---------|--------|
                | 1-4     | Complete |
                | 5-8     | Complete |
                | 9-12    | Complete |

                Thanks for scrolling through!
                """

                for chunk in Mock.chunk(markdown) {
                    guard !Task.isCancelled else { break }
                    try? await Task.sleep(for: Mock.textDelay)
                    continuation.yield(.textDelta(chunk))
                }

                continuation.yield(.finished(
                    usage: TokenUsage(promptTokens: 100, completionTokens: 2500),
                    finishReason: .stop
                ))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Slow response with 2s initial delay and slow chunks
    public static let delay_slow = Model.model(
        id: "mock.delay_slow",
        properties: [
            .displayName("Mock: Slow Delay"),
            .preferred
        ]
    ) { _, _ in
        AsyncThrowingStream { continuation in
            let task = Task {
                // Initial 2 second delay
                try? await Task.sleep(for: .seconds(2))

                guard !Task.isCancelled else {
                    continuation.finish()
                    return
                }

                let markdown = """
                # Finally responding...

                Sorry for the delay! I was thinking really hard.

                Here's what I came up with after all that time:

                1. First, I considered the problem deeply
                2. Then, I evaluated multiple approaches
                3. Finally, I arrived at this conclusion

                ```
                status: complete
                delay: 2000ms
                chunks: slow
                ```

                Hope that helps!
                """

                // Slow chunks (200ms each)
                for chunk in Mock.chunk(markdown, minSize: 3, maxSize: 8) {
                    guard !Task.isCancelled else { break }
                    try? await Task.sleep(for: .milliseconds(200))
                    continuation.yield(.textDelta(chunk))
                }

                continuation.yield(.finished(
                    usage: TokenUsage(promptTokens: 60, completionTokens: 100),
                    finishReason: .stop
                ))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

// MARK: - Tool Call Scenarios

extension Mock {
    /// Single tool call, then continue with response
    public static let tool_single = Model.model(
        id: "mock.tool_single",
        properties: [
            .displayName("Mock: Single Tool"),
            .preferred
        ]
    ) { items, _ in
        AsyncThrowingStream { continuation in
            let task = Task {
                if Mock.hasToolResult(in: items) {
                    // Continue after tool execution
                    let response = """
                    Based on the file contents, I can see this is a Swift project.

                    ## Analysis

                    The file structure shows:
                    - Standard Xcode project layout
                    - SwiftUI-based architecture
                    - Composable Architecture integration

                    Everything looks good!
                    """

                    for chunk in Mock.chunk(response) {
                        guard !Task.isCancelled else { break }
                        try? await Task.sleep(for: Mock.textDelay)
                        continuation.yield(.textDelta(chunk))
                    }

                    continuation.yield(.finished(
                        usage: TokenUsage(promptTokens: 150, completionTokens: 80),
                        finishReason: .stop
                    ))
                } else {
                    // Initial response - make tool call
                    let intro = "Let me check the project structure for you.\n\n"
                    for chunk in Mock.chunk(intro) {
                        guard !Task.isCancelled else { break }
                        try? await Task.sleep(for: Mock.textDelay)
                        continuation.yield(.textDelta(chunk))
                    }

                    try? await Task.sleep(for: Mock.toolDelay)

                    let toolId = "call_\(UUID().uuidString.prefix(8))"
                    let toolName = "read_file"
                    let arguments = """
                    {"path": "Package.swift"}
                    """

                    continuation.yield(.toolCallStart(id: toolId, name: toolName))
                    continuation.yield(.toolCallEnd(id: toolId, name: toolName, arguments: arguments))
                    continuation.yield(.finished(
                        usage: TokenUsage(promptTokens: 80, completionTokens: 40),
                        finishReason: .toolCalls
                    ))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Two parallel tool calls
    public static let tool_multiple = Model.model(
        id: "mock.tool_multiple",
        properties: [
            .displayName("Mock: Multiple Tools"),
            .preferred
        ]
    ) { items, _ in
        AsyncThrowingStream { continuation in
            let task = Task {
                if Mock.hasToolResult(in: items) {
                    // Continue after tool execution
                    let response = """
                    ## Comparison Results

                    After examining both files:

                    | File | Lines | Purpose |
                    |------|-------|---------|
                    | README.md | 45 | Project documentation |
                    | Package.swift | 30 | Swift package manifest |

                    Both files are properly configured!
                    """

                    for chunk in Mock.chunk(response) {
                        guard !Task.isCancelled else { break }
                        try? await Task.sleep(for: Mock.textDelay)
                        continuation.yield(.textDelta(chunk))
                    }

                    continuation.yield(.finished(
                        usage: TokenUsage(promptTokens: 200, completionTokens: 90),
                        finishReason: .stop
                    ))
                } else {
                    // Initial response - make multiple tool calls
                    let intro = "I'll read both files to compare them.\n\n"
                    for chunk in Mock.chunk(intro) {
                        guard !Task.isCancelled else { break }
                        try? await Task.sleep(for: Mock.textDelay)
                        continuation.yield(.textDelta(chunk))
                    }

                    try? await Task.sleep(for: Mock.toolDelay)

                    // First tool call
                    let toolId1 = "call_\(UUID().uuidString.prefix(8))"
                    continuation.yield(.toolCallStart(id: toolId1, name: "read_file"))
                    continuation.yield(.toolCallEnd(id: toolId1, name: "read_file", arguments: """
                    {"path": "README.md"}
                    """))

                    // Second tool call
                    let toolId2 = "call_\(UUID().uuidString.prefix(8))"
                    continuation.yield(.toolCallStart(id: toolId2, name: "read_file"))
                    continuation.yield(.toolCallEnd(id: toolId2, name: "read_file", arguments: """
                    {"path": "Package.swift"}
                    """))

                    continuation.yield(.finished(
                        usage: TokenUsage(promptTokens: 80, completionTokens: 60),
                        finishReason: .toolCalls
                    ))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Tool arguments arrive in chunks via toolCallDelta
    public static let tool_streaming = Model.model(
        id: "mock.tool_streaming",
        properties: [
            .displayName("Mock: Streaming Tool"),
            .preferred
        ]
    ) { items, _ in
        AsyncThrowingStream { continuation in
            let task = Task {
                if Mock.hasToolResult(in: items) {
                    let response = "The search found 3 matching files in the project."

                    for chunk in Mock.chunk(response) {
                        guard !Task.isCancelled else { break }
                        try? await Task.sleep(for: Mock.textDelay)
                        continuation.yield(.textDelta(chunk))
                    }

                    continuation.yield(.finished(
                        usage: TokenUsage(promptTokens: 120, completionTokens: 30),
                        finishReason: .stop
                    ))
                } else {
                    let intro = "Searching for files...\n\n"
                    for chunk in Mock.chunk(intro) {
                        guard !Task.isCancelled else { break }
                        try? await Task.sleep(for: Mock.textDelay)
                        continuation.yield(.textDelta(chunk))
                    }

                    let toolId = "call_\(UUID().uuidString.prefix(8))"
                    let toolName = "search_files"

                    // Stream the tool call start
                    continuation.yield(.toolCallStart(id: toolId, name: toolName))

                    // Stream arguments in chunks
                    let argumentParts = [
                        "{\"pat",
                        "tern\":",
                        " \"*.sw",
                        "ift\", ",
                        "\"dir\":",
                        " \"src/\"",
                        "}"
                    ]

                    for part in argumentParts {
                        guard !Task.isCancelled else { break }
                        try? await Task.sleep(for: .milliseconds(80))
                        continuation.yield(.toolCallDelta(id: toolId, args: part))
                    }

                    let fullArguments = """
                    {"pattern": "*.swift", "dir": "src/"}
                    """
                    continuation.yield(.toolCallEnd(id: toolId, name: toolName, arguments: fullArguments))
                    continuation.yield(.finished(
                        usage: TokenUsage(promptTokens: 70, completionTokens: 35),
                        finishReason: .toolCalls
                    ))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Text, then tool, then more text
    public static let mixed_textAndTools = Model.model(
        id: "mock.mixed_textAndTools",
        properties: [
            .displayName("Mock: Mixed Text & Tools"),
            .preferred
        ]
    ) { items, _ in
        AsyncThrowingStream { continuation in
            let task = Task {
                if Mock.hasToolResult(in: items) {
                    // After tool result, continue with analysis
                    let response = """

                    ## File Contents Analysis

                    The configuration file shows:

                    1. **Version**: 1.0.0
                    2. **Dependencies**: 3 packages
                    3. **Targets**: 2 (main + tests)

                    ```json
                    {
                      "status": "valid",
                      "warnings": 0
                    }
                    ```

                    All looks good! Let me know if you need anything else.
                    """

                    for chunk in Mock.chunk(response) {
                        guard !Task.isCancelled else { break }
                        try? await Task.sleep(for: Mock.textDelay)
                        continuation.yield(.textDelta(chunk))
                    }

                    continuation.yield(.finished(
                        usage: TokenUsage(promptTokens: 180, completionTokens: 120),
                        finishReason: .stop
                    ))
                } else {
                    // Initial: text, then tool
                    let intro = """
                    I'll help you analyze the project configuration.

                    First, let me explain what I'm looking for:
                    - Package dependencies
                    - Build targets
                    - Version information

                    Now let me read the config file:

                    """

                    for chunk in Mock.chunk(intro) {
                        guard !Task.isCancelled else { break }
                        try? await Task.sleep(for: Mock.textDelay)
                        continuation.yield(.textDelta(chunk))
                    }

                    try? await Task.sleep(for: Mock.toolDelay)

                    let toolId = "call_\(UUID().uuidString.prefix(8))"
                    continuation.yield(.toolCallStart(id: toolId, name: "read_file"))
                    continuation.yield(.toolCallEnd(id: toolId, name: "read_file", arguments: """
                    {"path": "config.json"}
                    """))

                    continuation.yield(.finished(
                        usage: TokenUsage(promptTokens: 90, completionTokens: 70),
                        finishReason: .toolCalls
                    ))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

// MARK: - Reasoning/Thinking

extension Mock {
    /// Reasoning delta events before text response
    public static let reasoning_simple = Model.model(
        id: "mock.reasoning_simple",
        properties: [
            .displayName("Mock: Reasoning"),
            .reasoning,
            .preferred
        ]
    ) { _, _ in
        AsyncThrowingStream { continuation in
            let task = Task {
                // Reasoning phase
                let reasoning = """
                Let me think through this step by step...

                First, I need to understand what the user is asking for.
                They want to understand how the system works.

                I should consider:
                1. The architecture of the application
                2. The key components and their interactions
                3. Best practices for this type of system

                Based on my analysis, I'll provide a clear explanation
                that covers the main concepts without overwhelming detail.
                """

                for chunk in Mock.chunk(reasoning, minSize: 5, maxSize: 15) {
                    guard !Task.isCancelled else { break }
                    try? await Task.sleep(for: .milliseconds(30))
                    continuation.yield(.reasoningDelta(chunk))
                }

                // Pause between reasoning and response
                try? await Task.sleep(for: .milliseconds(300))

                // Actual response
                let response = """
                # System Overview

                The system consists of three main components:

                ## 1. Model Layer
                Handles data structures and business logic.

                ## 2. View Layer
                Renders the UI using SwiftUI.

                ## 3. Feature Layer
                Coordinates state management with TCA.

                Each layer communicates through well-defined interfaces,
                making the system modular and testable.
                """

                for chunk in Mock.chunk(response) {
                    guard !Task.isCancelled else { break }
                    try? await Task.sleep(for: Mock.textDelay)
                    continuation.yield(.textDelta(chunk))
                }

                continuation.yield(.finished(
                    usage: TokenUsage(
                        promptTokens: 80,
                        completionTokens: 200,
                        details: ["reasoning_tokens": 150]
                    ),
                    finishReason: .stop
                ))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

// MARK: - Error Scenarios

extension Mock {
    /// Partial text then network error
    public static let error_network = Model.model(
        id: "mock.error_network",
        properties: [
            .displayName("Mock: Network Error"),
            .preferred
        ]
    ) { _, _ in
        AsyncThrowingStream { continuation in
            let task = Task {
                // Start with some text
                let partial = "I'm starting to process your reque"

                for chunk in Mock.chunk(partial) {
                    guard !Task.isCancelled else { break }
                    try? await Task.sleep(for: Mock.textDelay)
                    continuation.yield(.textDelta(chunk))
                }

                // Simulate network interruption
                try? await Task.sleep(for: .milliseconds(500))

                continuation.yield(.finished(usage: nil, finishReason: .error(LLMError(
                    code: "network_error",
                    message: "Connection lost. Please check your internet connection and try again.",
                    underlying: "URLError: The network connection was lost."
                ))))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Immediate rate limit (429) error
    public static let error_rateLimit = Model.model(
        id: "mock.error_rateLimit",
        properties: [
            .displayName("Mock: Rate Limit Error"),
            .preferred
        ]
    ) { _, _ in
        AsyncThrowingStream { continuation in
            let task = Task {
                // Small delay to simulate request being sent
                try? await Task.sleep(for: .milliseconds(100))

                continuation.yield(.finished(usage: nil, finishReason: .error(LLMError(
                    code: "rate_limit_exceeded",
                    message: "Rate limit exceeded. Please wait 60 seconds before trying again.",
                    underlying: "HTTP 429: Too Many Requests"
                ))))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Partial text then content filter
    public static let error_contentFilter = Model.model(
        id: "mock.error_contentFilter",
        properties: [
            .displayName("Mock: Content Filter"),
            .preferred
        ]
    ) { _, _ in
        AsyncThrowingStream { continuation in
            let task = Task {
                let partial = """
                I'd be happy to help you with that topic. Let me explain the basics of

                """

                for chunk in Mock.chunk(partial) {
                    guard !Task.isCancelled else { break }
                    try? await Task.sleep(for: Mock.textDelay)
                    continuation.yield(.textDelta(chunk))
                }

                try? await Task.sleep(for: .milliseconds(200))

                continuation.yield(.finished(
                    usage: TokenUsage(promptTokens: 50, completionTokens: 25),
                    finishReason: .contentFilter
                ))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

// MARK: - Edge Cases

extension Mock {
    /// Response truncated mid-word due to max tokens
    public static let finish_maxTokens = Model.model(
        id: "mock.finish_maxTokens",
        properties: [
            .displayName("Mock: Max Tokens"),
            .preferred
        ]
    ) { _, _ in
        AsyncThrowingStream { continuation in
            let task = Task {
                let text = """
                # The Complete Guide to Swift Programming

                ## Chapter 1: Introduction

                Swift is a powerful and intuitive programming language created by Apple.
                It's designed to be safe, fast, and expressive. In this comprehensive guide,
                we'll explore all the fundamental concepts you need to become proficient in Swift.

                ## Chapter 2: Variables and Constants

                In Swift, you can declare variables using `var` and constants using `let`:

                ```swift
                var mutableValue = 42
                let constantValue = "Hello"
                ```

                ## Chapter 3: Control Flow

                Swift provides several control flow statements inclu
                """

                for chunk in Mock.chunk(text) {
                    guard !Task.isCancelled else { break }
                    try? await Task.sleep(for: Mock.textDelay)
                    continuation.yield(.textDelta(chunk))
                }

                // Truncated mid-word with length finish reason
                continuation.yield(.finished(
                    usage: TokenUsage(promptTokens: 40, completionTokens: 150),
                    finishReason: .length
                ))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
