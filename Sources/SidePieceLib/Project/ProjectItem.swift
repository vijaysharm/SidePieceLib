//
//  ProjectItem.swift
//  SidePiece
//

import ComposableArchitecture
import Foundation

@Reducer
public struct ProjectItemFeature: Sendable {
    @ObservableState
    public struct State: Equatable, Identifiable {
        public let id: UUID
        var url: URL
        var isExpanded: Bool = true
        var conversationIDs: [UUID] = []

        var displayName: String { url.lastPathComponent }
    }

    public enum Action: Equatable {
        case toggleExpanded
    }

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .toggleExpanded:
                state.isExpanded.toggle()
                return .none
            }
        }
    }
}
