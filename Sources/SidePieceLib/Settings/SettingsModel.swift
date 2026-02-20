//
//  SettingsModel.swift
//  SidePiece
//

import ComposableArchitecture
import Foundation

protocol SettingIdentifiable: Hashable, Sendable, CustomStringConvertible {}

enum SettingType: Equatable, Sendable {
    case toggle(StorageKey<Bool>)
    case text(placeholder: String, StorageKey<String>)
    case dropdown(options: IdentifiedArrayOf<Option>, StorageKey<String>)
    case segmented(options: IdentifiedArrayOf<Option>, StorageKey<String>)
    case button(title: String) // I think should be sending out some kind of Action
    case secureText(placeholder: String, StorageKey<String>)

    struct Option: Equatable, Sendable, Identifiable {
        let id: String
        let title: String
    }
}

enum SettingValue: Equatable, Sendable {
    case bool(Bool)
    case string(String)
    case secure(String)
}

struct SettingItem: Equatable, Identifiable, Sendable {
    struct ID: Hashable, @unchecked Sendable, CustomStringConvertible {
        let id: AnyHashable
        let description: String

        init<H: SettingIdentifiable>(_ base: H) {
            self.id = AnyHashable(base)
            self.description = base.description
        }

        static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
        func hash(into hasher: inout Hasher) { hasher.combine(id) }
    }

    let id: ID
    let title: String
    let description: String
    let type: SettingType

    init(
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
    
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
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

struct SettingSection: Equatable, Identifiable, Sendable {
    struct ID: Hashable, @unchecked Sendable, CustomStringConvertible {
        let id: AnyHashable
        let description: String

        init<H: SettingIdentifiable>(_ base: H) {
            self.id = AnyHashable(base)
            self.description = base.description
        }

        static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
        func hash(into hasher: inout Hasher) { hasher.combine(id) }
    }

    let id: ID
    let title: String
    var items: IdentifiedArrayOf<SettingItem>

    init(id: ID, title: String, items: IdentifiedArrayOf<SettingItem>) {
        self.id = id
        self.title = title
        self.items = items
    }

    init(id: some SettingIdentifiable, title: String, items: IdentifiedArrayOf<SettingItem>) {
        self.id = ID(id)
        self.title = title
        self.items = items
    }
}

struct SettingCategory: Equatable, Identifiable, Sendable {
    struct ID: Hashable, @unchecked Sendable, CustomStringConvertible {
        let id: AnyHashable
        let description: String

        init<H: SettingIdentifiable>(_ base: H) {
            self.id = AnyHashable(base)
            self.description = base.description
        }

        static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
        func hash(into hasher: inout Hasher) { hasher.combine(id) }
    }

    let id: ID
    let title: String
    let icon: String
    var sections: IdentifiedArrayOf<SettingSection>

    init(id: ID, title: String, icon: String, sections: IdentifiedArrayOf<SettingSection>) {
        self.id = id
        self.title = title
        self.icon = icon
        self.sections = sections
    }

    init(id: some SettingIdentifiable, title: String, icon: String, sections: IdentifiedArrayOf<SettingSection>) {
        self.id = ID(id)
        self.title = title
        self.icon = icon
        self.sections = sections
    }
}
