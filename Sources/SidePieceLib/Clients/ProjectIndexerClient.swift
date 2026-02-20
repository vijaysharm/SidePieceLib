//
//  ProjectIndexerClient.swift
//  SidePiece
//

import Dependencies
import DependenciesMacros
import Foundation

@DependencyClient
public struct ProjectIndexerClient: Sendable {
    public var indexer: @Sendable () -> ProjectIndexer = { ProjectIndexer() }
}

extension ProjectIndexerClient: DependencyKey {
    public static let liveValue = {
        let indexer = ProjectIndexer()
        return ProjectIndexerClient(
            indexer: { indexer }
        )
    }()
}

extension DependencyValues {
    public var projectIndexerClient: ProjectIndexerClient {
        get { self[ProjectIndexerClient.self] }
        set { self[ProjectIndexerClient.self] = newValue }
    }
}

