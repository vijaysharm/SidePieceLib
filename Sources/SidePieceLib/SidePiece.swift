//
//  SidePiece.swift
//  SidePiece
//

import ComposableArchitecture
import SwiftUI

@Reducer
public struct SidePieceAppFeature: Sendable {
    @ObservableState
    public enum State: Equatable {
        case loading(LoadingFeature.State)
        case root(RootFeature.State)
    }
    
    public enum Action: Equatable {
        case loading(LoadingFeature.Action)
        case root(RootFeature.Action)
    }
    
    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .loading(.delegate(.ready(data))):
                state = .root(data)
                return .none
            case .loading:
                return .none
            case .root:
                return .none
            }
        }
        .ifCaseLet(\.loading, action: \.loading) {
            LoadingFeature()
        }
        .ifCaseLet(\.root, action: \.root) {
            RootFeature()
        }
    }
}

public struct SidePieceAppView: View {
    @Bindable var store: StoreOf<SidePieceAppFeature>
    private let appTheme: Theme

    public init(
        store: StoreOf<SidePieceAppFeature>,
        theme: Theme = .dark
    ) {
        self.store = store
        self.appTheme = theme
    }

    public var body: some View {
        Group {
            switch store.state {
            case .loading:
                if let store = store.scope(state: \.loading, action: \.loading) {
                    LoadingView(store: store)
                }
            case .root:
                if let store = store.scope(state: \.root, action: \.root) {
                    RootView(store: store)
                }
            }
        }
        .theme(appTheme)
    }
}
