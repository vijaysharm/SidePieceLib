//
//  ModelSelection.swift
//  SidePiece
//

import ComposableArchitecture
import SwiftUI

@Reducer
public struct ModelSelectionFeature: Sendable {
    public struct DisplayModel: Equatable, Sendable, Identifiable {
        let model: Model

        public var id: String { model.id.description }
        var name: String { model.displayName }
        var family: String? { model.family }

        var hasReasoning: Bool { model.hasReasoning }
        var hasToolCalling: Bool { model.hasToolCalling }
        var hasVision: Bool { model.hasVision }
        var hasPDFSupport: Bool { model.hasPDFSupport }
        var hasImageGeneration: Bool { model.hasImageGeneration }

        var isFast: Bool {
            let fastIndicators = ["mini", "flash", "instant", "haiku", "small"]
            return fastIndicators.contains { name.lowercased().contains($0) }
        }

        var descriptionText: String {
            model.descriptionText
        }

        var cost: (input: Decimal, output: Decimal)? { model.cost }
        var contextWindow: Int? { model.contextWindow }

        var contextWindowText: String? {
            guard let ctx = contextWindow else { return nil }
            if ctx >= 1_000_000 {
                return "\(ctx / 1_000_000)M ctx"
            } else if ctx >= 1_000 {
                return "\(ctx / 1_000)K ctx"
            }
            return "\(ctx) ctx"
        }

        var costText: String? {
            guard let cost = cost, cost.input != 0 || cost.output != 0 else { return nil }
            let fmt = { (d: Decimal) -> String in
                let nsn = d as NSDecimalNumber
                let v = nsn.doubleValue
                if v < 0.01 {
                    return String(format: "$%.3f", v)
                } else if v == v.rounded(.down) {
                    return String(format: "$%.0f", v)
                } else {
                    return String(format: "$%.2f", v)
                }
            }
            return "\(fmt(cost.input))/\(fmt(cost.output))"
        }
    }

    public enum ModelCategory: Equatable, Sendable, Hashable {
        case preferred
        case provider(String)

        var displayName: String {
            switch self {
            case .preferred:
                return "Preferred"
            case let .provider(id):
                return id.capitalized
            }
        }

        var tabLetter: String {
            switch self {
            case .preferred:
                return "P"
            case let .provider(id):
                return String(id.prefix(1)).uppercased()
            }
        }
    }
    
    @ObservableState
    public struct State: Equatable, Sendable {
        public struct Source: Equatable, Sendable {
            let inputId: ContextInputFeature.State.ID
            let conversationId: ConversationFeature.State.ID
        }

        let source: Source
        let allModels: [DisplayModel]
        var searchText: String = ""
        var selectedCategory: ModelCategory = .preferred
        var selectedModel: Model? = nil
        var isArchivedExpanded: Bool = false

        var isTabBarVisible: Bool {
            searchText.isEmpty
        }

        var availableCategories: [ModelCategory] {
            var categories: [ModelCategory] = []
            if allModels.contains(where: { $0.model.isPreferred && !$0.model.isArchived }) {
                categories.append(.preferred)
            }
            let providerIDs = Set(allModels.map(\.model.providerId))
            let sortedProviders = providerIDs.sorted { $0 < $1 }
            categories += sortedProviders.map { .provider($0) }
            return categories
        }

        var effectiveSelectedCategory: ModelCategory {
            if availableCategories.contains(selectedCategory) {
                return selectedCategory
            }
            return availableCategories.first ?? selectedCategory
        }

        var filteredModels: [DisplayModel] {
            let searchLower = searchText.lowercased()
            if searchLower.isEmpty {
                return allModels
            }
            return allModels.filter { model in
                model.name.lowercased().contains(searchLower) ||
                model.model.providerName.lowercased().contains(searchLower) ||
                (model.family?.lowercased().contains(searchLower) ?? false)
            }
        }

        var modelsForSelectedCategory: [DisplayModel] {
            let models = filteredModels.filter { !$0.model.isArchived }

            if !searchText.isEmpty {
                return models
            }

            switch effectiveSelectedCategory {
            case .preferred:
                return models.filter(\.model.isPreferred)
            case .provider(let providerID):
                return models.filter { $0.model.providerId == providerID }
            }
        }

        var archivedModels: [DisplayModel] {
            filteredModels.filter(\.model.isArchived)
        }
    }

    public enum Action: Equatable, Sendable {
        @CasePathable
        public enum DelegateAction: Equatable, Sendable {
            case modelSelected(State.Source, Model)
            case showModelInfo(Model)
            case dismiss
        }

        @CasePathable
        public enum InternalAction: Equatable, Sendable {
            case searchTextChanged(String)
            case selectCategory(ModelCategory)
            case selectModel(Model)
            case toggleArchivedSection
            case showModelInfo(String)
        }

        case `internal`(InternalAction)
        case delegate(DelegateAction)
    }

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .internal(.searchTextChanged(text)):
                state.searchText = text
                return .none

            case let .internal(.selectCategory(category)):
                state.selectedCategory = category
                return .none

            case let .internal(.selectModel(model)):
                state.selectedModel = model
                if let model = state.allModels.first(where: { $0.model == model }) {
                    return .send(.delegate(.modelSelected(state.source, model.model)))
                }
                return .none

            case .internal(.toggleArchivedSection):
                state.isArchivedExpanded.toggle()
                return .none

            case let .internal(.showModelInfo(id)):
                if let model = state.allModels.first(where: { $0.id == id }) {
                    return .send(.delegate(.showModelInfo(model.model)))
                }
                return .none

            case .delegate:
                return .none
            }
        }
    }
}

// MARK: - Main View

struct ModelSelectionView: View {
    @Bindable var store: StoreOf<ModelSelectionFeature>
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            SearchField(
                text: $store.searchText.sending(\.internal.searchTextChanged)
            )
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            
            HStack(spacing: 0) {
                if store.isTabBarVisible {
                    CategoryTabBar(store: store)
                        .transition(
                            .move(edge: .leading).combined(with: .opacity)
                        )
                }
                Divider()
                    .opacity(0.5)

                VStack(spacing: 0) {
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(store.modelsForSelectedCategory) { model in
                                ModelRowView(
                                    model: model,
                                    isSelected: store.selectedModel == model.model,
                                    store: store
                                )
                            }
                            
                            if !store.archivedModels.isEmpty {
                                ArchivedSection(store: store)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    }
                    HStack {
                        Text("Prices are approximate. Refer to provider websites for current pricing.")
                            .font(.system(size: 8))
                            .foregroundStyle(.tertiary)
                            .padding(.leading)
                        Spacer()
                        Button(role: .cancel) {
                            store.send(.delegate(.dismiss))
                        } label: {
                            Text("Cancel")
                        }
                    }
                    .padding([.bottom, .trailing])
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: store.isTabBarVisible)
        .background(theme.surfaceBackground)
    }
}

// MARK: - Search Field

private struct SearchField: View {
    @Binding var text: String
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 14))

            TextField("Search models...", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(theme.surfaceSecondary)
        )
    }
}

// MARK: - Category Tab Bar

private struct CategoryTabBar: View {
    @Bindable var store: StoreOf<ModelSelectionFeature>
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 4) {
                    ForEach(store.availableCategories, id: \.self) { category in
                        CategoryTabButton(
                            category: category,
                            isSelected: store.effectiveSelectedCategory == category,
                            store: store
                        )
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 6)
            }
            Spacer()
        }
        .background(theme.surfaceBackground.opacity(0.5))
    }
}

// MARK: - Category Tab Button

private struct CategoryTabButton: View {
    let category: ModelSelectionFeature.ModelCategory
    let isSelected: Bool
    @Bindable var store: StoreOf<ModelSelectionFeature>

    @Environment(\.theme) private var theme
    @State private var isHovered = false

    var body: some View {
        Button {
            store.send(.internal(.selectCategory(category)))
        } label: {
            ZStack {
                if isSelected {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(theme.selectedFill)
                } else if isHovered {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(theme.hoverFill)
                }

                HStack(spacing: 0) {
                    if isSelected {
                        Rectangle()
                            .fill(theme.tabIndicator)
                            .frame(width: 3)
                            .clipShape(RoundedRectangle(cornerRadius: 1.5))
                    }

                    Spacer()

                    Group {
                        if case .preferred = category {
                            Image(systemName: "star.fill")
                                .font(.system(size: 14))
                        } else {
                            Text(category.tabLetter)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                        }
                    }
                    .foregroundStyle(isSelected ? .primary : .secondary)

                    Spacer()
                }
            }
            .frame(width: 40, height: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.08)) {
                isHovered = hovering
            }
        }
        .help(category.displayName)
    }
}

// MARK: - Model Row View

private struct ModelRowView: View {
    let model: ModelSelectionFeature.DisplayModel
    let isSelected: Bool
    @Bindable var store: StoreOf<ModelSelectionFeature>

    @Environment(\.theme) private var theme
    @State private var localHover = false

    private var isHighlighted: Bool {
        isSelected || localHover
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(model.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(isSelected ? .white : .primary)
                        .lineLimit(1)
                    Spacer()
                    FeatureIconsView(model: model, isHighlighted: isSelected)
                }

                HStack {
                    Text(model.descriptionText)
                        .font(.system(size: 11))
                        .foregroundStyle(isSelected ? .white.opacity(0.7) : .secondary)
                        .lineLimit(1)

                    if let ctx = model.contextWindowText {
                        Text("·")
                            .foregroundStyle(isSelected ? Color.white.opacity(0.5) : Color.secondary.opacity(0.5))
                        Text(ctx)
                            .font(.system(size: 11))
                            .foregroundStyle(isSelected ? .white.opacity(0.7) : .secondary)
                    }

                    if let cost = model.costText {
                        Text("·")
                            .foregroundStyle(isSelected ? Color.white.opacity(0.5) : Color.secondary.opacity(0.5))
                        Text(cost)
                            .font(.system(size: 11))
                            .foregroundStyle(isSelected ? .white.opacity(0.7) : .secondary)
                    }

                    Spacer()
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? theme.selectedFill : (isHighlighted ? theme.hoverFill : Color.clear))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            store.send(.internal(.selectModel(model.model)))
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.08)) {
                localHover = hovering
            }
        }
    }
}

// MARK: - Feature Icons View

private struct FeatureIconsView: View {
    let model: ModelSelectionFeature.DisplayModel
    let isHighlighted: Bool
    @Environment(\.theme) private var theme

    private var hasAnyFeature: Bool {
        model.isFast || model.hasVision || model.hasReasoning ||
        model.hasToolCalling || model.hasImageGeneration || model.hasPDFSupport
    }

    var body: some View {
        if hasAnyFeature {
            HStack(spacing: 2) {
                if model.isFast {
                    FeatureIcon(systemName: "bolt.fill", color: .yellow, tooltip: "Fast")
                }
                if model.hasVision {
                    FeatureIcon(systemName: "eye", color: .green, tooltip: "Vision")
                }
                if model.hasReasoning {
                    FeatureIcon(systemName: "brain", color: .purple, tooltip: "Reasoning")
                }
                if model.hasToolCalling {
                    FeatureIcon(systemName: "wrench", color: Color(red: 0.9, green: 0.5, blue: 0.5), tooltip: "Tool Calling")
                }
                if model.hasImageGeneration {
                    FeatureIcon(systemName: "photo.badge.plus", color: .purple.opacity(0.8), tooltip: "Image Generation")
                }
                if model.hasPDFSupport {
                    FeatureIcon(systemName: "doc.text", color: .cyan, tooltip: "PDF Comprehension")
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(theme.featureIconCapsule)
            )
        }
    }
}

private struct FeatureIcon: View {
    let systemName: String
    let color: Color
    let tooltip: String

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.2))
                .frame(width: 18, height: 18)

            Image(systemName: systemName)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(color)
        }
        .help(tooltip)
    }
}

// MARK: - Archived Section

private struct ArchivedSection: View {
    @Bindable var store: StoreOf<ModelSelectionFeature>

    var body: some View {
        VStack(spacing: 0) {
            Button {
                store.send(.internal(.toggleArchivedSection))
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: store.isArchivedExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)

                    Image(systemName: "archivebox")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)

                    Text("\(store.archivedModels.count) archived models")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    Spacer()
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if store.isArchivedExpanded {
                ForEach(store.archivedModels) { model in
                    ModelRowView(
                        model: model,
                        isSelected: store.selectedModel == model.model,
                        store: store
                    )
                    .opacity(0.6)
                }
            }
        }
    }
}
