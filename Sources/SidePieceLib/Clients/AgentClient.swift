//
//  AgentClient.swift
//  SidePiece
//

import Dependencies
import DependenciesMacros

@DependencyClient
public struct AgentClient: Sendable {
    var agents: @Sendable () async throws -> Agents
}

extension AgentClient: DependencyKey {
    public static let liveValue = AgentClient(
        agents: {
            .agents([.defaultAsk], default: .defaultAsk)
        }
    )
}

extension DependencyValues {
    public var agentClient: AgentClient {
        get { self[AgentClient.self] }
        set { self[AgentClient.self] = newValue }
    }
}
