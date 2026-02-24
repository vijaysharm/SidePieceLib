//
//  ToolRegistryClient.swift
//  SidePiece
//

import Dependencies
import DependenciesMacros
import Foundation

@DependencyClient
public struct ToolRegistryClient: Sendable {
    public var register: @Sendable (Tool) -> Void
    public var execute: @Sendable (_ name: String, _ arguments: String, _ userResponse: String?, _ projectURL: URL) async throws -> String

    /// Returns the interaction type declared by the named tool, or `.permission` if unknown.
    public var interaction: @Sendable (_ name: String) -> ToolInteraction = { _ in .permission }
}

extension ToolRegistryClient: DependencyKey {
    public static let liveValue = {
        let registry = LockIsolated<[Tool.ID: Tool]>([:])
        return ToolRegistryClient(
            register: { tool in
                registry.withValue {
                    $0[tool.id] = tool
                }
            },
            execute: { name, arguments, userResponse, projectURL in
                guard let tool = registry.withValue({
                    $0[name]
                }) else {
                    throw ToolExecutionError.unknown("Unknown tool: \(name)")
                }

                return try await tool.execute(arguments, userResponse, projectURL)
            },
            interaction: { name in
                registry.withValue {
                    $0[name]?.interaction ?? .permission
                }
            }
        )
    }()

    public static let testValue = ToolRegistryClient()
}

extension DependencyValues {
    public var toolRegistryClient: ToolRegistryClient {
        get { self[ToolRegistryClient.self] }
        set { self[ToolRegistryClient.self] = newValue }
    }
}
