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
    public let execute: @Sendable (_ arguments: String, _ directory: URL) async throws -> String
    
    public static func == (lhs: Tool, rhs: Tool) -> Bool {
        lhs.definition.name == rhs.definition.name
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(definition)
    }
}
