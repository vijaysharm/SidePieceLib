//
//  ResponseBlock.swift
//  SidePiece
//

import ComposableArchitecture
import Foundation

@Reducer
struct ResponseBlockFeature {
    @ObservableState
    enum State: Identifiable, Equatable {
        case text(TextBlockFeature.State)
        case reasoning(ReasoningBlockFeature.State)
        case toolCall(ToolCallBlockFeature.State)
        case error(ErrorBlockFeature.State)
        
        var id: UUID {
            switch self {
            case let .text(data):
                data.id
            case let .reasoning(data):
                data.id
            case let .toolCall(data):
                data.id
            case let .error(data):
                data.id
            }
        }
    }
    
    enum Action: Equatable {
        case text(TextBlockFeature.Action)
        case reasoning(ReasoningBlockFeature.Action)
        case toolCall(ToolCallBlockFeature.Action)
        case error(ErrorBlockFeature.Action)
    }
    
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .text:
                return .none
            case .reasoning:
                return .none
            case .toolCall:
                return .none
            case .error:
                return .none
            }
        }
        .ifCaseLet(\.text, action: \.text) {
            TextBlockFeature()
        }
        .ifCaseLet(\.reasoning, action: \.reasoning) {
            ReasoningBlockFeature()
        }
        .ifCaseLet(\.toolCall, action: \.toolCall) {
            ToolCallBlockFeature()
        }
        .ifCaseLet(\.error, action: \.error) {
            ErrorBlockFeature()
        }
    }
}
