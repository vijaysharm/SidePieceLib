//
//  SettingsSidebarView.swift
//  SidePiece
//

import ComposableArchitecture
import SwiftUI

struct SettingsSidebarView: View {
    let store: StoreOf<SettingsFeature>

    var body: some View {
        VStack(spacing: 0) {
            // Back button
            Button {
                store.send(.delegate(.dismiss))
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Back to app")
                        .font(.subheadline)
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.top, 12)

            // Title
            Text("Settings")
                .font(.title2)
                .fontWeight(.bold)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 12)

            // Category list
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(store.categories) { category in
                        SettingsCategoryRow(
                            category: category,
                            isSelected: store.selectedCategoryID == category.id,
                            onSelect: {
                                store.send(.internal(.selectCategory(id: category.id)))
                            }
                        )
                    }
                }
                .padding(.horizontal, 8)
            }

            Spacer()
        }
    }
}

struct SettingsCategoryRow: View {
    let category: SettingCategory
    let isSelected: Bool
    let onSelect: () -> Void

    @Environment(\.theme) private var theme
    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                Image(systemName: category.icon)
                    .font(.system(size: 14))
                    .foregroundStyle(isSelected ? .white : .secondary)
                    .frame(width: 20)

                Text(category.title)
                    .font(.subheadline)
                    .foregroundStyle(isSelected ? .white : .primary)
                    .lineLimit(1)

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(
                        isSelected
                            ? theme.selectedFill
                            : (isHovered ? theme.hoverFill : Color.clear)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.08)) {
                isHovered = hovering
            }
        }
    }
}
