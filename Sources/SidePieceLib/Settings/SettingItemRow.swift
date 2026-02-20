//
//  SettingItemRow.swift
//  SidePiece
//

import ComposableArchitecture
import SwiftUI

struct SettingItemRow: View {
    let item: SettingItem
    let categoryID: SettingCategory.ID
    let sectionID: SettingSection.ID
    let store: StoreOf<SettingsFeature>

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            switch item.type {
            case .toggle:
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.subheadline)
                        if !item.description.isEmpty {
                            Text(item.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if let value = store.settingItemValues[item.id], case let .bool(value) = value {
                        Toggle("", isOn: Binding(
                            get: { value },
                            set: { newValue in
                                store.send(.internal(.updateSetting(
                                    itemID: item.id,
                                    value: .bool(newValue)
                                )))
                            }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    }
                }

            case let .text(placeholder, _):
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.subheadline)
                    if !item.description.isEmpty {
                        Text(item.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let value = store.settingItemValues[item.id], case let .string(value) = value {
                        TextField(placeholder, text: Binding(
                            get: { value },
                            set: { newValue in
                                store.send(.internal(.updateSetting(
                                    itemID: item.id,
                                    value: .string(newValue)
                                )))
                            }
                        ))
                        .textFieldStyle(.roundedBorder)
                    }
                }

            case let .dropdown(options, _), let .segmented(options, _):
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.subheadline)
                        if !item.description.isEmpty {
                            Text(item.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if let value = store.settingItemValues[item.id], case let .string(value) = value {
                        Picker("", selection: Binding(
                            get: { value },
                            set: { newValue in
                                store.send(.internal(.updateSetting(
                                    itemID: item.id,
                                    value: .string(newValue)
                                )))
                            }
                        )) {
                            ForEach(options) { option in
                                Text(option.title).tag(option.id)
                            }
                        }
                        .settingItemStyle(item)
                        .frame(maxWidth: 200)
                    }
                }

            case let .button(title):
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.subheadline)
                        if !item.description.isEmpty {
                            Text(item.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button(title) {
                        store.send(.internal(.settingButtonTapped(
                            categoryID: categoryID,
                            sectionID: sectionID,
                            itemID: item.id
                        )))
                    }
                }

            case let .secureText(placeholder, _):
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.title)
                        .font(.subheadline)
                        .fontWeight(.bold)
                    if !item.description.isEmpty {
                        Text(item.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                
                    if let value = store.settingItemValues[item.id], case let .secure(value) = value {
                        HStack(spacing: 8) {
                            TextField(placeholder, text: Binding(
                                get: { value },
                                set: { newValue in
                                    store.send(.internal(.updateSetting(
                                        itemID: item.id,
                                        value: .secure(newValue)
                                    )))
                                }
                            ))
                            .textFieldStyle(.roundedBorder)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }
}

extension Picker {
    func settingItemStyle(_ item: SettingItem) -> some View {
        guard case .segmented = item.type else {
            return AnyView(self.pickerStyle(.automatic))
        }
        return AnyView(self.pickerStyle(.segmented))
    }
}
