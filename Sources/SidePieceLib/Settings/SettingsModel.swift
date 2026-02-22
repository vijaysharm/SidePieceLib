//
//  SettingsModel.swift
//  SidePiece
//

import ComposableArchitecture
import Foundation

public protocol SettingIdentifiable: Hashable, Sendable, CustomStringConvertible {}

public enum SettingType: Equatable, Sendable {
    case toggle(StorageKey<Bool>)
    case text(placeholder: String, StorageKey<String>)
    case dropdown(options: IdentifiedArrayOf<Option>, StorageKey<String>)
    case segmented(options: IdentifiedArrayOf<Option>, StorageKey<String>)
    case button(title: String) // I think should be sending out some kind of Action
    case secureText(placeholder: String, StorageKey<String>)

    public struct Option: Equatable, Sendable, Identifiable {
        public let id: String
        let title: String
    }
}

public enum SettingValue: Equatable, Sendable {
    case bool(Bool)
    case string(String)
    case secure(String)
}

public struct SettingItem: Equatable, Identifiable, Sendable {
    public struct ID: Hashable, @unchecked Sendable, CustomStringConvertible {
        public let id: AnyHashable
        public let description: String

        public init<H: SettingIdentifiable>(_ base: H) {
            self.id = AnyHashable(base)
            self.description = base.description
        }

        public static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
        public func hash(into hasher: inout Hasher) { hasher.combine(id) }
    }

    public let id: ID
    let title: String
    let description: String
    let type: SettingType

    public init(
        id: some SettingIdentifiable,
        title: String,
        description: String,
        type: SettingType
    ) {
        self.id = ID(id)
        self.title = title
        self.description = description
        self.type = type
    }
    
    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
}

extension SettingItem {
    func write(_ value: SettingValue) throws {
        switch type {
            case let .toggle(key):
                switch value {
                case let .bool(value):
                    try key.write(value)
                case .string, .secure:
                    break
                }
            case let .text(_, key),
                let .dropdown(_, key),
                let .segmented(_, key),
                let .secureText(_, key):
                switch value {
                case .bool:
                    break
                case let .string(value), let .secure(value):
                    try key.write(value)
                }
            case .button: // I think should be sending out some kind of Action:
                break
        }
    }
}

public struct SettingSection: Equatable, Identifiable, Sendable {
    public struct ID: Hashable, @unchecked Sendable, CustomStringConvertible {
        public let id: AnyHashable
        public let description: String

        init<H: SettingIdentifiable>(_ base: H) {
            self.id = AnyHashable(base)
            self.description = base.description
        }

        public static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
        public func hash(into hasher: inout Hasher) { hasher.combine(id) }
    }

    public let id: ID
    let title: String
    var items: IdentifiedArrayOf<SettingItem>

    public init(id: ID, title: String, items: IdentifiedArrayOf<SettingItem>) {
        self.id = id
        self.title = title
        self.items = items
    }

    public init(id: some SettingIdentifiable, title: String, items: IdentifiedArrayOf<SettingItem>) {
        self.id = ID(id)
        self.title = title
        self.items = items
    }
}

public struct SettingCategory: Equatable, Identifiable, Sendable {
    public struct ID: Hashable, @unchecked Sendable, CustomStringConvertible {
        public let id: AnyHashable
        public let description: String

        public init<H: SettingIdentifiable>(_ base: H) {
            self.id = AnyHashable(base)
            self.description = base.description
        }

        public static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
        public func hash(into hasher: inout Hasher) { hasher.combine(id) }
    }

    public let id: ID
    let title: String
    let icon: String
    var sections: IdentifiedArrayOf<SettingSection>

    public init(id: ID, title: String, icon: String, sections: IdentifiedArrayOf<SettingSection>) {
        self.id = id
        self.title = title
        self.icon = icon
        self.sections = sections
    }

    public init(id: some SettingIdentifiable, title: String, icon: String, sections: IdentifiedArrayOf<SettingSection>) {
        self.id = ID(id)
        self.title = title
        self.icon = icon
        self.sections = sections
    }
}
