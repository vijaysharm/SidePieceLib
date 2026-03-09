//
//  ReasoningBlock.swift
//  SidePiece
//

import ComposableArchitecture
import SwiftUI

@Reducer
public struct ReasoningBlockFeature: Sendable {
    @ObservableState
    public struct State: Identifiable, Equatable, Sendable {
        public let id: UUID
        var content: String
        var isStreaming: Bool
        var isExpanded: Bool
    }
    
    public enum Action: Equatable, Sendable {
        @CasePathable
        public enum DelegateAction: Equatable, Sendable {}

        @CasePathable
        public enum InternalAction: Equatable, Sendable {
            case toggleExpanded
        }

        case `internal`(InternalAction)
        case delegate(DelegateAction)
    }
    
    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .internal(.toggleExpanded):
                state.isExpanded.toggle()
                return .none
            case .internal, .delegate:
                return .none
            }
        }
    }
}

struct ReasoningBlockView: View {
    @Bindable var store: StoreOf<ReasoningBlockFeature>
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.md) {
            HStack(spacing: theme.spacing.md) {
                Button {
                    store.send(.internal(.toggleExpanded), animation: .easeInOut(duration: 0.2))
                } label: {
                    HStack(spacing: 8) {
                        Text("Thinking")
                            .foregroundStyle(.secondary)
                        
                        if store.isStreaming {
                            ProgressView()
                                .controlSize(.mini)
                        }
                        
                        Image(systemName: store.isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
                
                Spacer()
            }
            .animation(nil, value: store.isExpanded)

            if store.isExpanded {
                Text(store.content)
                    .font(theme.typography.bodySmall)
                    .foregroundStyle(.secondary)
                    .padding(.leading, theme.spacing.xxl)
                    .textSelection(.enabled)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    ScrollView {
        VStack {
            ReasoningBlockView(store: Store(initialState: ReasoningBlockFeature.State(
                id: UUID(),
                content: "Let me think about this...",
                isStreaming: true,
                isExpanded: true
            )) {
                ReasoningBlockFeature()
            })
            ReasoningBlockView(store: Store(initialState: ReasoningBlockFeature.State(
                id: UUID(),
                content: "I've finished thinking.",
                isStreaming: false,
                isExpanded: false
            )) {
                ReasoningBlockFeature()
            })
        }
    }
    .padding()
}
