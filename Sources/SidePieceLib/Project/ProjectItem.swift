//
//  ProjectItem.swift
//  SidePiece
//

import ComposableArchitecture
import Foundation

@Reducer
struct ProjectItemFeature {
    @ObservableState
    struct State: Equatable, Identifiable {
        let id: UUID
        var url: URL
        var isExpanded: Bool = true
        var conversationIDs: [UUID] = []

        var displayName: String { url.lastPathComponent }
    }

    enum Action: Equatable {
        case toggleExpanded
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .toggleExpanded:
                state.isExpanded.toggle()
                return .none
            }
        }
    }
}
