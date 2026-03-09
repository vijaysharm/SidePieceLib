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
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            switch item.type {
            case .toggle:
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(theme.typography.bodySmall)
                        if !item.description.isEmpty {
                            Text(item.description)
                                .font(theme.typography.caption)
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

            case let .text(placeholder, options, _):
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(theme.typography.bodySmall)
                    if !item.description.isEmpty {
                        Text(item.description)
                            .font(theme.typography.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let value = store.settingItemValues[item.id], case let .string(value) = value {
                        let binding = Binding(
                            get: { value },
                            set: { newValue in
                                store.send(.internal(.updateSetting(
                                    itemID: item.id,
                                    value: .string(newValue)
                                )))
                            }
                        )
                        if options.contains(.multiline) {
                            TextEditor(text: binding)
                                .font(theme.typography.bodySmall)
                                .scrollContentBackground(.hidden)
                                .padding(.horizontal, theme.spacing.md)
                                .padding(.vertical, theme.spacing.sm)
                                .frame(minHeight: 120)
                                .background(theme.colors.backgroundInput)
                                .clipShape(RoundedRectangle(cornerRadius: theme.radius.sm))
                                .overlay(
                                    RoundedRectangle(cornerRadius: theme.radius.sm)
                                        .stroke(theme.colors.borderSubtle, lineWidth: theme.borderWidth.hairline)
                                )
                        } else {
                            TextField(placeholder, text: binding)
                                .textFieldStyle(.plain)
                                .padding(.horizontal, theme.spacing.md)
                                .padding(.vertical, theme.spacing.sm)
                                .background(theme.colors.backgroundInput)
                                .clipShape(RoundedRectangle(cornerRadius: theme.radius.sm))
                                .overlay(
                                    RoundedRectangle(cornerRadius: theme.radius.sm)
                                        .stroke(theme.colors.borderSubtle, lineWidth: theme.borderWidth.hairline)
                                )
                        }
                    }
                }

            case let .dropdown(options, _), let .segmented(options, _):
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(theme.typography.bodySmall)
                        if !item.description.isEmpty {
                            Text(item.description)
                                .font(theme.typography.caption)
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
                        .frame(maxWidth: 200, alignment: .trailing)
                    }
                }

            case let .button(title):
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(theme.typography.bodySmall)
                        if !item.description.isEmpty {
                            Text(item.description)
                                .font(theme.typography.caption)
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
                        .font(theme.typography.bodySmall)
                        .fontWeight(.bold)
                    if !item.description.isEmpty {
                        Text(item.description)
                            .font(theme.typography.caption)
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
                            .textFieldStyle(.plain)
                            .padding(.horizontal, theme.spacing.md)
                            .padding(.vertical, theme.spacing.sm)
                            .background(theme.colors.backgroundInput)
                            .clipShape(RoundedRectangle(cornerRadius: theme.radius.sm))
                            .overlay(
                                RoundedRectangle(cornerRadius: theme.radius.sm)
                                    .stroke(theme.colors.borderSubtle, lineWidth: theme.borderWidth.hairline)
                            )
                        }
                    }
                }
            case let .label(title):
                HStack {
                    Text(item.title)
                        .font(theme.typography.bodySmall)
                    Spacer()
                    Text(title)
                        .font(theme.typography.bodySmall)
                        .foregroundStyle(.secondary)
                }

            case let .link(title, url):
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(theme.typography.bodySmall)
                        Text(item.description)
                            .font(theme.typography.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Link(title, destination: url)
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
