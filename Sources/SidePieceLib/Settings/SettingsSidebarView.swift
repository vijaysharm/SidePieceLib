//
//  SettingsSidebarView.swift
//  SidePiece
//

import ComposableArchitecture
import SwiftUI

struct SettingsSidebarView: View {
    let store: StoreOf<SettingsFeature>
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            // Back button
            Button {
                store.send(.delegate(.dismiss))
            } label: {
                HStack(spacing: theme.spacing.sm) {
                    Image(systemName: "chevron.left")
                        .font(theme.typography.caption)
                        .fontWeight(.semibold)
                    Text("Back to app")
                        .font(theme.typography.bodySmall)
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, theme.spacing.lg)
                .padding(.vertical, theme.spacing.md)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, theme.spacing.md)
            .padding(.top, theme.spacing.lg)

            // Title
            Text("Settings")
                .font(theme.typography.titleSmall)
                .fontWeight(.bold)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, theme.spacing.md)
                .padding(.bottom, theme.spacing.lg)

            // Category list
            ScrollView {
                LazyVStack(spacing: theme.spacing.xxs) {
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
                .padding(.horizontal, theme.spacing.md)
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
                    .font(theme.typography.label)
                    .foregroundStyle(isSelected ? theme.colors.textOnSelected : .secondary)
                    .frame(width: 20)

                Text(category.title)
                    .font(theme.typography.bodySmall)
                    .foregroundStyle(isSelected ? theme.colors.textOnSelected : .primary)
                    .lineLimit(1)

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, theme.spacing.md)
            .background(
                RoundedRectangle(cornerRadius: theme.radius.sm)
                    .fill(
                        isSelected
                            ? theme.colors.surfaceSelected
                            : (isHovered ? theme.colors.surfaceHover : Color.clear)
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
