//
//  SettingsDetailView.swift
//  SidePiece
//

import ComposableArchitecture
import SwiftUI

struct SettingsDetailView: View {
    let category: SettingCategory
    let store: StoreOf<SettingsFeature>

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Category heading
                Text(category.title)
                    .font(.title)
                    .fontWeight(.bold)
                    .padding(.bottom, 4)

                // Sections
                ForEach(category.sections) { section in
                    SettingsSectionCard(
                        section: section,
                        categoryID: category.id,
                        store: store
                    )
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct SettingsSectionCard: View {
    let section: SettingSection
    let categoryID: SettingCategory.ID
    let store: StoreOf<SettingsFeature>

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section title
            Text(section.title)
                .font(.headline)
                .fontWeight(.semibold)
                .padding(.bottom, 8)

            // Items in a grouped card
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(section.items.enumerated()), id: \.element.id) { index, item in
                    SettingItemRow(
                        item: item,
                        categoryID: categoryID,
                        sectionID: section.id,
                        store: store
                    )
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)

                    if index < section.items.count - 1 {
                        Divider()
                            .padding(.horizontal, 12)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
        }
    }
}
