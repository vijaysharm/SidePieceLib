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

    /// Resolves the interaction type from the tool's arguments.
    /// Called after the LLM emits a tool call, before presenting to the user.
    /// Returns `.permission` for tools that don't need special interaction.
    public let resolveInteraction: @Sendable (_ arguments: String) -> ToolInteraction

    /// Executes the tool with final arguments (including any merged user response).
    ///
    /// - Parameters:
    ///   - arguments: The raw JSON argument string, potentially enriched with
    ///     user input merged under the interaction's `argumentKey`.
    ///   - directory: The project root URL.
    /// - Returns: The tool result as a string.
    public let execute: @Sendable (_ arguments: String, _ directory: URL) async throws -> String

    public init(
        definition: ToolDefinition,
        resolveInteraction: @escaping @Sendable (_ arguments: String) -> ToolInteraction = { _ in .permission },
        execute: @escaping @Sendable (_ arguments: String, _ directory: URL) async throws -> String
    ) {
        self.definition = definition
        self.resolveInteraction = resolveInteraction
        self.execute = execute
    }

    public static func == (lhs: Tool, rhs: Tool) -> Bool {
        lhs.definition.name == rhs.definition.name
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(definition)
    }
}
