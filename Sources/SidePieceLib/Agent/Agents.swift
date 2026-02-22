//
//  Agents.swift
//  SidePiece
//


public struct Agents: Equatable, Sendable {
    public let agents: [Agent]
    public let `default`: Agent
    
    public init(agents: [Agent], `default`: Agent) {
        self.agents = agents
        self.default = `default`
    }
}

extension Agents {
    public static func agents(
        _ agents: [Agent],
        default: Agent
    ) -> Self {
        .init(agents: agents, default: `default`)
    }
}
