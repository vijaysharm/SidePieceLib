//
//  InMemoryKeyValueClient.swift
//  SidePiece
//

import Dependencies
import DependenciesMacros
import Foundation

@DependencyClient
public struct InMemoryKeyValueClient: Sendable {
    public protocol InMemoryKey: Hashable, Sendable, CustomStringConvertible {}
    private let memory = LockIsolated<[String: Data]>([:])
    
    public func save(_ key: some InMemoryKey, _ data: Data) throws -> Void {
        memory.withValue {
            $0[key.description] = data
        }
    }

    public func read(_ key: some InMemoryKey) throws -> Data? {
        memory.withValue {
            $0[key.description]
        }
    }

    public func delete(_ key: some InMemoryKey) throws -> Void {
        _ = memory.withValue {
            $0.removeValue(forKey: key.description)
        }
    }

    public func exists(_ key: some InMemoryKey) throws -> Bool {
        memory.withValue {
            $0[key.description] != nil
        }
    }
}

extension InMemoryKeyValueClient: DependencyKey {
    public static let liveValue = InMemoryKeyValueClient()
}

extension DependencyValues {
    public var inMemoryClient: InMemoryKeyValueClient {
        get { self[InMemoryKeyValueClient.self] }
        set { self[InMemoryKeyValueClient.self] = newValue }
    }
}
