//
//  SettingsDetailView.swift
//  SidePiece
//

import ComposableArchitecture
import SwiftUI

struct SettingsDetailView: View {
    let category: SettingCategory
    let store: StoreOf<SettingsFeature>
    @Environment(\.theme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.spacing.xxl) {
                // Category heading
                Text(category.title)
                    .font(theme.typography.title)
                    .fontWeight(.bold)
                    .padding(.bottom, theme.spacing.xs)

                // Sections
                ForEach(category.sections) { section in
                    SettingsSectionCard(
                        section: section,
                        categoryID: category.id,
                        store: store
                    )
                }
            }
            .padding(theme.spacing.xxl)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct SettingsSectionCard: View {
    let section: SettingSection
    let categoryID: SettingCategory.ID
    let store: StoreOf<SettingsFeature>
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section title
            if !section.title.isEmpty {
                Text(section.title)
                    .font(theme.typography.heading)
                    .fontWeight(.semibold)
                    .padding(.bottom, theme.spacing.md)
            }

            // Items in a grouped card
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(section.items.enumerated()), id: \.element.id) { index, item in
                    SettingItemRow(
                        item: item,
                        categoryID: categoryID,
                        sectionID: section.id,
                        store: store
                    )
                    .padding(.horizontal, theme.spacing.lg)
                    .padding(.vertical, theme.spacing.md)

                    if index < section.items.count - 1 {
                        Divider()
                            .padding(.horizontal, theme.spacing.lg)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: theme.radius.md)
                    .fill(theme.colors.surfaceSubtle)
            )
            .overlay(
                RoundedRectangle(cornerRadius: theme.radius.md)
                    .stroke(theme.colors.borderSubtle, lineWidth: theme.borderWidth.thin)
            )
        }
    }
}
