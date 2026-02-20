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
    
    public init(
        name: String,
        color: Color,
        icon: Image,
        tools: [Tool]
    ) {
        self.name = name
        self.color = color
        self.icon = icon
        self.tools = tools
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
        ]
    )
}
