//
//  ResponseBlock.swift
//  SidePiece
//

import ComposableArchitecture
import Foundation

@Reducer
public struct ResponseBlockFeature: Sendable {
    @ObservableState
    public enum State: Identifiable, Equatable, Sendable {
        case text(TextBlockFeature.State)
        case reasoning(ReasoningBlockFeature.State)
        case toolCall(ToolCallBlockFeature.State)
        case error(ErrorBlockFeature.State)
        
        public var id: UUID {
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
    
    public enum Action: Equatable, Sendable {
        case text(TextBlockFeature.Action)
        case reasoning(ReasoningBlockFeature.Action)
        case toolCall(ToolCallBlockFeature.Action)
        case error(ErrorBlockFeature.Action)
    }
    
    public var body: some ReducerOf<Self> {
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
