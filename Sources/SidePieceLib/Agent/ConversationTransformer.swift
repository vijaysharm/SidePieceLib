//
//  ConversationTransformer.swift
//  SidePiece
//
//  Normalizes conversation history for cross-provider compatibility.
//  Handles tool call ID sanitization, orphaned tool calls, and
//  thinking block conversion when switching between providers.
//

import Foundation

/// Normalizes `[ConversationItem]` for safe replay across different LLM providers.
///
/// Different providers have incompatible requirements:
/// - **Tool call IDs:** OpenAI generates 450+ char IDs with special characters;
///   Anthropic requires `^[a-zA-Z0-9_-]+$` max 64 chars; Mistral requires exactly 9 alphanum.
/// - **Orphaned tool calls:** When a user interrupts mid-tool-call, the conversation
///   may contain tool calls without matching results, which causes API errors.
/// - **Thinking blocks:** Reasoning content from one provider may not be understood
///   by another (e.g., redacted thinking blocks from Anthropic).
public enum ConversationTransformer {

    /// Target provider format for ID normalization.
    public enum TargetProvider: Sendable {
        /// Anthropic: `^[a-zA-Z0-9_-]+$`, max 64 characters
        case anthropic
        /// Mistral: exactly 9 alphanumeric characters
        case mistral
        /// OpenAI and most compatible providers: no strict format requirements
        case openAI
        /// Custom regex and length constraints
        case custom(maxLength: Int, allowedCharacters: CharacterSet)
    }

    // MARK: - Public API

    /// Transforms conversation items for safe use with the target provider.
    ///
    /// Applies all normalizations in sequence:
    /// 1. Sanitize tool call IDs for target provider format
    /// 2. Repair orphaned tool calls (add synthetic error results)
    /// 3. Optionally strip or convert thinking/reasoning content
    ///
    /// - Parameters:
    ///   - items: The raw conversation history.
    ///   - target: The target provider format.
    ///   - stripThinking: Whether to remove reasoning content entirely.
    ///     When `false`, reasoning is preserved as-is (for same-provider replay).
    /// - Returns: Normalized conversation items safe for the target provider.
    public static func transform(
        _ items: [ConversationItem],
        for target: TargetProvider,
        stripThinking: Bool = false
    ) -> [ConversationItem] {
        var result = items

        // 1. Normalize tool call IDs
        result = normalizeToolCallIds(result, for: target)

        // 2. Repair orphaned tool calls
        result = repairOrphanedToolCalls(result)

        // 3. Strip empty messages
        result = stripEmptyMessages(result)

        return result
    }

    // MARK: - Tool Call ID Normalization

    /// Rewrites tool call IDs to conform to the target provider's format requirements.
    static func normalizeToolCallIds(
        _ items: [ConversationItem],
        for target: TargetProvider
    ) -> [ConversationItem] {
        // Build a mapping from original IDs to normalized IDs
        var idMapping: [String: String] = [:]
        var counter = 0

        func normalizedId(for original: String) -> String {
            if let existing = idMapping[original] { return existing }
            let normalized = sanitizeId(original, for: target, index: counter)
            counter += 1
            idMapping[original] = normalized
            return normalized
        }

        return items.map { item in
            switch item {
            case .message:
                return item
            case .toolCall(let id, let name, let arguments):
                return .toolCall(id: normalizedId(for: id), name: name, arguments: arguments)
            case .toolResult(let id, let output):
                return .toolResult(id: normalizedId(for: id), output: output)
            }
        }
    }

    private static func sanitizeId(_ id: String, for target: TargetProvider, index: Int) -> String {
        switch target {
        case .openAI:
            // OpenAI is lenient, but cap at reasonable length
            if id.count <= 256 { return id }
            return String(id.prefix(256))

        case .anthropic:
            // ^[a-zA-Z0-9_-]+$, max 64 chars
            let sanitized = id.unicodeScalars
                .filter { CharacterSet.alphanumerics.contains($0) || $0 == "_" || $0 == "-" }
                .map(String.init)
                .joined()
            if sanitized.isEmpty {
                return "tool_\(index)"
            }
            return String(sanitized.prefix(64))

        case .mistral:
            // Exactly 9 alphanumeric characters
            let alphanum = id.unicodeScalars
                .filter { CharacterSet.alphanumerics.contains($0) }
                .map(String.init)
                .joined()
            if alphanum.count >= 9 {
                return String(alphanum.prefix(9))
            }
            // Pad with hash-derived characters
            let hash = stableHash(id)
            let padded = alphanum + hash
            return String(padded.prefix(9))

        case .custom(let maxLength, let allowed):
            let sanitized = id.unicodeScalars
                .filter { allowed.contains($0) }
                .map(String.init)
                .joined()
            if sanitized.isEmpty {
                return "tool_\(index)"
            }
            return String(sanitized.prefix(maxLength))
        }
    }

    /// Produce a stable alphanumeric hash from a string (for padding short IDs).
    private static func stableHash(_ input: String) -> String {
        var hash: UInt64 = 5381
        for byte in input.utf8 {
            hash = hash &* 33 &+ UInt64(byte)
        }
        let chars = "abcdefghijklmnopqrstuvwxyz0123456789"
        var result = ""
        var h = hash
        for _ in 0..<16 {
            let index = Int(h % UInt64(chars.count))
            result.append(chars[chars.index(chars.startIndex, offsetBy: index)])
            h /= UInt64(chars.count)
        }
        return result
    }

    // MARK: - Orphaned Tool Call Repair

    /// Finds tool calls without matching results and inserts synthetic error results.
    ///
    /// This handles the case where a user interrupts the assistant mid-tool-call,
    /// leaving the conversation with orphaned tool calls that cause API errors
    /// on the next request.
    static func repairOrphanedToolCalls(_ items: [ConversationItem]) -> [ConversationItem] {
        // Collect all tool call IDs and tool result IDs
        var toolCallIds: [(index: Int, id: String, name: String)] = []
        var toolResultIds: Set<String> = []

        for (i, item) in items.enumerated() {
            switch item {
            case .toolCall(let id, let name, _):
                toolCallIds.append((index: i, id: id, name: name))
            case .toolResult(let id, _):
                toolResultIds.insert(id)
            case .message:
                break
            }
        }

        // Find orphaned tool calls (no matching result)
        let orphaned = toolCallIds.filter { !toolResultIds.contains($0.id) }

        if orphaned.isEmpty { return items }

        // Insert synthetic error results after the last orphaned tool call
        var result = items
        // Process in reverse so indices remain valid
        for orphan in orphaned.reversed() {
            let syntheticResult = ConversationItem.toolResult(
                id: orphan.id,
                output: "[Error: Tool call was interrupted before completion]"
            )
            // Insert result right after the tool call
            let insertIndex = min(orphan.index + 1, result.endIndex)
            result.insert(syntheticResult, at: insertIndex)
        }

        return result
    }

    // MARK: - Empty Message Stripping

    /// Remove messages with empty content arrays (can happen after thinking block removal).
    static func stripEmptyMessages(_ items: [ConversationItem]) -> [ConversationItem] {
        items.filter { item in
            if case .message(_, let content) = item {
                return !content.isEmpty
            }
            return true
        }
    }
}

