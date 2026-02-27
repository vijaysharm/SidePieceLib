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
    public var execute: @Sendable (_ name: String, _ arguments: String, _ projectURL: URL) async throws -> String

    /// Resolves the interaction type for the named tool given its arguments,
    /// or `.permission` if the tool is unknown.
    public var resolveInteraction: @Sendable (_ name: String, _ arguments: String) -> ToolInteraction = { _, _ in .permission }
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
            execute: { name, arguments, projectURL in
                guard let tool = registry.withValue({
                    $0[name]
                }) else {
                    throw ToolExecutionError.unknown("Unknown tool: \(name)")
                }

                return try await tool.execute(arguments, projectURL)
            },
            resolveInteraction: { name, arguments in
                registry.withValue {
                    $0[name]?.resolveInteraction(arguments) ?? .permission
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
