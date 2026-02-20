//
//  Agents.swift
//  SidePiece
//


public struct Agents: Equatable, Sendable {
    let agents: [Agent]
    let `default`: Agent
}

extension Agents {
    public static func agents(
        _ agents: [Agent],
        default: Agent
    ) -> Self {
        .init(agents: agents, default: `default`)
    }
}
