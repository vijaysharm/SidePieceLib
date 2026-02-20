//
//  UserPreferencesClient.swift
//  SidePiece
//

import Dependencies
import DependenciesMacros
import Foundation

@DependencyClient
public struct UserPreferencesClient: Sendable {
    public protocol UserPrefernceKey: Hashable, Sendable, CustomStringConvertible {}
    private let defaults: LockIsolated<UserDefaults>

    nonisolated init(defaults: LockIsolated<UserDefaults>) {
        self.defaults = defaults
    }
    
    public func get(_ key: some UserPrefernceKey) -> Data? {
        defaults.withValue {
            $0.data(forKey: key.description)
        }
    }

    public func set(_ value: Data?, for key: some UserPrefernceKey) {
        defaults.withValue {
            $0.set(value, forKey: key.description)
        }
    }
    
    public func clearAll() async {
        defaults.withValue { defaults in
            guard let bundleId = Bundle.main.bundleIdentifier else { return }
            defaults.removePersistentDomain(forName: bundleId)
        }
    }
}

extension UserPreferencesClient: DependencyKey {
    public static let liveValue = UserPreferencesClient(
        defaults: LockIsolated<UserDefaults>(.standard)
    )
}

extension DependencyValues {
    public var userPreferencesClient: UserPreferencesClient {
        get { self[UserPreferencesClient.self] }
        set { self[UserPreferencesClient.self] = newValue }
    }
}
