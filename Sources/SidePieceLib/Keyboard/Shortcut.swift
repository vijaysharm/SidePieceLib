//
//  Shortcut.swift
//  SidePiece
//

import ComposableArchitecture
import Foundation

@Reducer
struct ShortcutFeature {
    @ObservableState
    struct State: Equatable, Sendable {
        var shortcuts: [KeyboardShortcut]
    }
    
    enum Action: Equatable, Sendable {
        case start
        case stop
        case delegate(DelegateAction)
        
        @CasePathable
        enum DelegateAction: Equatable, Sendable {
            case shortcut(KeyboardShortcut)
        }
    }
    
    enum CancelID {
        case events
    }

    @Dependency(\.keyboardClient) var keyboardClient
    
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .start:
                let canConsume: @Sendable (KeyboardShortcut) -> Bool = { [shortcuts = state.shortcuts] event in
                    shortcuts.contains(event)
                }
                return .run { send in
                    for await event in keyboardClient.start(canConsume) {
                        await send(.delegate(.shortcut(event)))
                    }
                }.cancellable(id: CancelID.events)
            case .stop:
                return .cancel(id: CancelID.events)
            case .delegate:
                return .none
            }
        }
        // TODO: This needs to be handled by a parent
//        .onChange(of: \.shortcuts) { _, _ in
//            Reduce { _, _ in
//                .concatenate([
//                    .send(.stop),
//                    .send(.start)
//                ])
//            }
//        }
    }
}
