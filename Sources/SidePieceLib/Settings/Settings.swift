//
//  Settings.swift
//  SidePiece
//

import ComposableArchitecture
import SwiftUI

@Reducer
struct SettingsFeature: Sendable {
    @ObservableState
    struct State: Equatable {
        var categories: IdentifiedArrayOf<SettingCategory>
        var selectedCategoryID: SettingCategory.ID?
        var settingItemValues: [SettingItem.ID: SettingValue] = [:]
        var modifiedSettingItemIDs: Set<SettingItem.ID> = []
        var selectedCategory: SettingCategory? {
            selectedCategoryID.flatMap { categories[id: $0] }
        }
        
        init(
            categories: IdentifiedArrayOf<SettingCategory>,
            selectedCategoryID: SettingCategory.ID? = nil
        ) {
            self.categories = categories
            self.selectedCategoryID = selectedCategoryID ?? categories.first?.id
        }
    }

    enum Action: Equatable, Sendable {
        case loadStoredKeyStatuses
        
        @CasePathable
        enum DelegateAction: Equatable, Sendable {
            case dismiss
        }

        @CasePathable
        enum InternalAction: Equatable, Sendable {
            case selectCategory(id: SettingCategory.ID)
            case updateSetting(itemID: SettingItem.ID, value: SettingValue)
            case settingButtonTapped(
                categoryID: SettingCategory.ID,
                sectionID: SettingSection.ID,
                itemID: SettingItem.ID
            )
        }

        case `internal`(InternalAction)
        case delegate(DelegateAction)
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .internal(.selectCategory(id)):
                state.selectedCategoryID = id
                return .none

            case let .internal(.updateSetting(itemID, value)):
                state.settingItemValues[itemID] = value
                state.modifiedSettingItemIDs.insert(itemID)
                return .none

            case .internal(.settingButtonTapped):
                return .none

            case .loadStoredKeyStatuses:
                // TODO: Should be done async (key.read can go to disk)
                let result = state.categories.reduce(into: [SettingItem.ID: SettingValue]()) { result, next in
                    result = next.sections.reduce(into: result) { result, next in
                        result = next.items.reduce(into: result) { result, next in
                            switch next.type {
                            case let .toggle(key):
                                guard let value = try? key.read() else { break }
                                result[next.id] = .bool(value)
                            case let .text(_, key), let .segmented(_, key), let .dropdown(_, key):
                                guard let value = try? key.read() else { break }
                                result[next.id] = .string(value)
                            case let .secureText(_, key):
                                guard let value = try? key.read() else { break }
                                result[next.id] = .secure(maskedPreview(for: value))
                            case .button:
                                break
                            }
                        }
                    }
                }
                state.settingItemValues = result
                return .none

            case .delegate:
                return .none
            }
        }
    }

    private func maskedPreview(for value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        guard trimmed.count > 7 else { return "***" }
        let prefix = String(trimmed.prefix(3))
        let suffix = String(trimmed.suffix(4))
        return "\(prefix)...\(suffix)"
    }
}

struct SettingsView: View {
    @Bindable var store: StoreOf<SettingsFeature>

    var body: some View {
        NavigationSplitView {
            SettingsSidebarView(store: store)
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 300)
        } detail: {
            if let category = store.selectedCategory {
                SettingsDetailView(category: category, store: store)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "gear")
                        .font(.system(size: 36))
                        .foregroundStyle(.tertiary)
                    Text("Select a category")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 660)
        .navigationTitle("")
        .toolbarTitleDisplayMode(.inline)
    }
}

#Preview {
    SidePieceView()
        .frame(width: 900, height: 500)
}
