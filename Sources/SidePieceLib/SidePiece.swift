//
//  SidePiece.swift
//  SidePiece
//

import ComposableArchitecture
import SwiftUI

@Reducer
struct SidePieceAppFeature {
    @ObservableState
    enum State: Equatable {
        case loading(LoadingFeature.State)
        case root(RootFeature.State)
    }
    
    enum Action: Equatable {
        case loading(LoadingFeature.Action)
        case root(RootFeature.Action)
    }
    
    var body: some ReducerOf<Self> {
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

struct SidePieceAppView: View {
    @Bindable var store: StoreOf<SidePieceAppFeature>
    
    var body: some View {
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
}
