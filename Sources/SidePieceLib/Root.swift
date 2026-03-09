//
//  Root.swift
//  SidePiece
//

import ComposableArchitecture
import SwiftUI

@Reducer
public struct RootFeature: Sendable {
    @Reducer
    public enum Destination {
        case imageOverlay(ImageOverlayFeature)
        case modelSelection(ModelSelectionFeature)
        case deleteConfirmation(DeleteConfirmationFeature)
        case directorySelection(DirectoryModalFeature)
    }

    @ObservableState
    public struct State: Equatable {
        public enum Page: Equatable, Sendable {
            case project
            case settings
        }
        var page: Page = .project
        var project: ProjectFeature.State
        var settings: SettingsFeature.State
        var shortcuts = ShortcutFeature.State(
            shortcuts: [
                .nextAgent, .closeOpenDialogs, .openSettings
            ]
        )
        @Presents var destination: Destination.State?
    }

    public enum Action: Equatable {
        case onAppear
        case onDisappear
        case dismissModelSelection
        case project(ProjectFeature.Action)
        case settings(SettingsFeature.Action)
        case shortcuts(ShortcutFeature.Action)
        case destination(PresentationAction<Destination.Action>)
        case `internal`(InternalAction)
        
        @CasePathable
        public enum InternalAction: Equatable {
            case ready
        }
    }

    public var body: some ReducerOf<Self> {
        Scope(state: \.project, action: \.project) {
            ProjectFeature()
        }
        Scope(state: \.settings, action: \.settings) {
            SettingsFeature()
        }
        Scope(state: \.shortcuts, action: \.shortcuts) {
            ShortcutFeature()
        }
        Reduce { state, action in
            switch action {
            case .onAppear:
                return .concatenate(
                    .merge(
                        // TODO: I wonder if these should be done sequentially
                        // TODO: Maybe only when we support changing shortcuts through settings
                        .send(.settings(.loadStoredKeyStatuses)),
                        .send(.shortcuts(.start)),
                    ),
                    .send(.internal(.ready))
                )
            case .onDisappear:
                return .send(.shortcuts(.stop))
            case .project(.delegate(.settings)):
                guard case .project = state.page else { return .none }
                state.page = .settings
                return .none
            case let .project(.delegate(.viewImage(url))):
                state.destination = .imageOverlay(ImageOverlayFeature.State(url: url))
                return .none
            case .project(.delegate(.selectDirectory)):
                state.destination = .directorySelection(DirectoryModalFeature.State())
                return .none
            case let .project(.conversations(.element(_, .delegate(.selectModel(source, current))))):
                state.destination = .modelSelection(ModelSelectionFeature.State(
                    source: source,
                    allModels: state.project.models.models.map {
                        ModelSelectionFeature.DisplayModel(model: $0)
                    },
                    selectedModel: current
                ))
                return .none
            case .settings(.delegate(.dismiss)):
                guard case .settings = state.page else { return .none }
                state.page = .project
                // TODO: Saving the settings should be done on background thread
                // TODO: This also means that settings are not saved until the user leaves the settings view
                for category in state.settings.categories {
                    for section in category.sections {
                        for item in section.items {
                            if let value = state.settings.settingItemValues[item.id],
                               state.settings.modifiedSettingItemIDs.contains(item.id) {
                                try? item.write(value)
                            }
                        }
                    }
                }
                state.settings.modifiedSettingItemIDs.removeAll()
                return .none
            case let .destination(.presented(.directorySelection(.recentProjectsSelection(.delegate(.openUrl(url)))))):
                state.destination = nil
                return .send(.project(.addProject(url)))

            case .destination(.presented(.directorySelection(.cancel))):
                guard case .directorySelection = state.destination else { return .none }
                state.destination = nil
                return .none

            case .destination(.presented(.imageOverlay(.dismiss))):
                state.destination = nil
                return .none
            case let .destination(.presented(.modelSelection(.delegate(.modelSelected(source, model))))):
                guard case .modelSelection = state.destination else { return .none }
                state.destination = nil
                return .send(.project(.applyModelSelection(source: source, model: model)))
            case .destination(.presented(.modelSelection(.delegate(.dismiss)))):
                guard case .modelSelection = state.destination else { return .none }
                state.destination = nil
                return .none
            case .dismissModelSelection:
                guard case .modelSelection = state.destination else { return .none }
                state.destination = nil
                return .none
            case let .project(.delegate(.confirmDeleteConversation(id, title))):
                state.destination = .deleteConfirmation(DeleteConfirmationFeature.State(
                    kind: .conversation(id: id, title: title)
                ))
                return .none
            case let .project(.delegate(.confirmRemoveProject(id, title, url))):
                state.destination = .deleteConfirmation(DeleteConfirmationFeature.State(
                    kind: .project(id: id, title: title, url: url)
                ))
                return .none
            case let .destination(.presented(.deleteConfirmation(.delegate(.confirmDeleteConversation(id))))):
                state.destination = nil
                return .send(.project(.deleteConversation(id)))
            case let .destination(.presented(.deleteConfirmation(.delegate(.confirmRemoveProject(id, url))))):
                state.destination = nil
                return .send(.project(.removeProject(id: id, url: url)))
            case .destination(.presented(.deleteConfirmation(.cancel))):
                state.destination = nil
                return .none
            case .shortcuts(.delegate(.shortcut(.closeOpenDialogs))):
                state.destination = nil
                guard let id = state.project.selectedConversationID else { return .none }
                return .merge(
                    .send(.project(.conversations(.element(id: id, action: .dismissContextMenu)))),
                    reduce(into: &state, action: .settings(.delegate(.dismiss)))
                )
            case .shortcuts(.delegate(.shortcut(.nextAgent))):
                guard let conversationID = state.project.selectedConversationID else { return .none }
                return .send(.project(.conversations(.element(id: conversationID, action: .mainTextView(.agentToolbar(.selectNextAgent))))))
            case .shortcuts(.delegate(.shortcut(.openSettings))):
                return reduce(into: &state, action: .project(.delegate(.settings)))
            case .internal:
                return .none
            case .shortcuts:
                return .none
            case .settings:
                return .none
            case .project:
                return .none
            case .destination:
                return .none
            }
        }
        .ifLet(\.$destination, action: \.destination)
    }
}

extension RootFeature.Destination.State: Equatable {}
extension RootFeature.Destination.Action: Equatable {}

struct RootView: View {
    @Bindable var store: StoreOf<RootFeature>
    @Environment(\.theme) private var theme

    var body: some View {
        Group {
            switch store.state.page {
            case .project:
                ProjectView(store: store.scope(state: \.project, action: \.project))
            case .settings:
                SettingsView(store: store.scope(state: \.settings, action: \.settings))
            }
        }
        .onAppear {
            store.send(.onAppear)
        }
        .onDisappear {
            store.send(.onDisappear)
        }
        .overlay {
            if let overlayStore = store.scope(
                state: \.destination?.imageOverlay,
                action: \.destination.imageOverlay
            ) {
                ImageOverlayView(store: overlayStore)
                    .ignoresSafeArea()
            }
        }
        .overlay {
            if let modelStore = store.scope(
                state: \.destination?.modelSelection,
                action: \.destination.modelSelection
            ) {
                ZStack {
                    theme.colors.scrim
                        .contentShape(Rectangle())
                        .onTapGesture {
                            store.send(.dismissModelSelection)
                        }
                        .transition(.opacity)
                    ModelSelectionView(store: modelStore)
                        .frame(width: 450, height: 400)
                        .clipShape(RoundedRectangle(cornerRadius: theme.radius.lg))
                        .transition(.opacity.combined(with: .offset(y: -8)))
                }
                .ignoresSafeArea()
            }
        }
        .sheet(item: $store.scope(
            state: \.destination?.directorySelection,
            action: \.destination.directorySelection)
        ) { store in
            DirectoryModalView(store: store)
                .frame(minHeight: 300)
        }
        .overlay {
            if let deleteStore = store.scope(
                state: \.destination?.deleteConfirmation,
                action: \.destination.deleteConfirmation
            ) {
                ZStack {
                    theme.colors.scrim
                        .contentShape(Rectangle())
                        .onTapGesture {
                            store.send(.destination(.presented(.deleteConfirmation(.cancel))))
                        }
                        .transition(.opacity)
                    DeleteConfirmationView(store: deleteStore)
                        .frame(width: 340)
                        .transition(.opacity.combined(with: .offset(y: -8)))
                }
                .ignoresSafeArea()
            }
        }
        .animation(.easeOut(duration: 0.2), value: store.destination != nil)
    }
}

extension StorageKey where T == String {
    public static func keyChainStorageKey(_ id: String) -> Self {
        StorageKey(id: id) { id in
            @Dependency(\.keychainClient) var keychainClient
            guard let data = try? keychainClient.read(id) else { return "" }
            guard let string = String(data: data, encoding: .utf8) else { return "" }
            return string
        } write: { id, key in
            @Dependency(\.keychainClient) var keychainClient
            guard let data = key.data(using: .utf8) else { return }
            try? keychainClient.save(id, data)
        }
    }
}

extension KeyboardShortcut {
    public static let nextAgent = KeyboardShortcut(key: .tab, modifiers: [.shift])
    public static let closeOpenDialogs = KeyboardShortcut(key: .escape)
    public static let openSettings = KeyboardShortcut(key: .comma, modifiers: [.command])
}
