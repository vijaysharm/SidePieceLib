//
//  Tool.swift
//  SidePiece
//

import Foundation

public struct Tool: Identifiable, Hashable, Sendable {
    public var id: String {
        definition.name
    }

    public let definition: ToolDefinition

    /// The type of interaction this tool requires from the user before execution.
    /// Defaults to `.permission` (the standard Allow/Deny gate).
    public let interaction: ToolInteraction

    /// Executes the tool.
    ///
    /// - Parameters:
    ///   - arguments: The raw JSON argument string from the LLM.
    ///   - userResponse: The user's response for interactive tools (`.textInput`, `.choice`).
    ///     `nil` for permission-based tools where the user simply approved.
    ///   - directory: The project root URL.
    /// - Returns: The tool result as a string.
    public let execute: @Sendable (_ arguments: String, _ userResponse: String?, _ directory: URL) async throws -> String

    public init(
        definition: ToolDefinition,
        interaction: ToolInteraction = .permission,
        execute: @escaping @Sendable (_ arguments: String, _ userResponse: String?, _ directory: URL) async throws -> String
    ) {
        self.definition = definition
        self.interaction = interaction
        self.execute = execute
    }

    public static func == (lhs: Tool, rhs: Tool) -> Bool {
        lhs.definition.name == rhs.definition.name
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(definition)
    }
}
