//
//  Agent.swift
//  SidePiece
//

import Foundation
import SwiftUI

public struct Agent: Hashable, Sendable {
    public let name: String
    public let color: Color
    public let icon: Image
    public let tools: [Tool]

    /// Maximum agentic loop turns before the loop stops automatically.
    /// Each turn is one LLM call that results in tool calls followed by a restart.
    /// Set to 0 for no limit (not recommended).
    public let maxTurns: Int

    public init(
        name: String,
        color: Color,
        icon: Image,
        tools: [Tool],
        maxTurns: Int = 25
    ) {
        self.name = name
        self.color = color
        self.icon = icon
        self.tools = tools
        self.maxTurns = maxTurns
    }
    
    // Hash only by name since Image/Color aren't Hashable
    // and name should be the unique identifier
    public func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
    
    public static func == (lhs: Agent, rhs: Agent) -> Bool {
        lhs.name == rhs.name
    }
}

public extension Agent {
    static let defaultAsk = Agent(
        name: "Ask",
        color: .green,
        icon: Image(systemName: "message"),
        tools: [
            .readFile,
            .fileSearch,
            .globFileSearch,
            .grep,
            .codebaseFileSearch,
            .listDirectory
        ],
        maxTurns: 10
    )

    static let defaultCode = Agent(
        name: "Code",
        color: .blue,
        icon: Image(systemName: "terminal"),
        tools: [
            .readFile,
            .fileSearch,
            .globFileSearch,
            .grep,
            .codebaseFileSearch,
            .listDirectory,
            .writeFile,
            .editFile,
            .bash,
            .askUserQuestion,
        ],
        maxTurns: 25
    )
}
