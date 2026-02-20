//
//  StorageKey.swift
//  SidePiece
//

import Foundation

public protocol StorageKeyIdentifiable: Hashable, Sendable, CustomStringConvertible {}

public struct StorageKeyIdentifier: StorageKeyIdentifiable, Identifiable, @unchecked Sendable {
    public let id: AnyHashable
    public let description: String

    init<H>(_ base: H) where H : Hashable & Sendable & CustomStringConvertible {
        self.id = AnyHashable(base)
        self.description = base.description
    }
}

public struct StorageKey<T: Hashable & Sendable>: Sendable, Identifiable, Hashable {
    public let id: StorageKeyIdentifier
    let read: @Sendable () throws -> T
    let write: @Sendable (T) throws -> Void
    
    init(
        id: any StorageKeyIdentifiable,
        read: @escaping @Sendable (StorageKeyIdentifier) throws -> T,
        write: @escaping @Sendable (StorageKeyIdentifier, T) throws -> Void
    ) {
        self.id = .init(id)
        self.read = {
            return try read(.init(id))
        }
        self.write = { data in
            try write(.init(id), data)
        }
    }
    
    public static func == (lhs: StorageKey<T>, rhs: StorageKey<T>) -> Bool {
        lhs.id == rhs.id
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

extension StorageKey {
    public enum StorageKeyError: LocalizedError {
        case dataNotFound
    }
}

extension String: StorageKeyIdentifiable {}
extension StorageKeyIdentifier: UserPreferencesClient.UserPrefernceKey {}
extension StorageKeyIdentifier: KeychainClient.KeychainKey {}
extension StorageKeyIdentifier: InMemoryKeyValueClient.InMemoryKey {}
