//
//  ContextAgentToolbar.swift
//  SidePiece
//

import ComposableArchitecture
import SwiftUI

@Reducer
struct ContextAgentToolbarFeature: Sendable {
    @ObservableState
    struct State: Equatable, Sendable {
        var selectedAgent: Agent
        var availableAgents: [Agent] {
            agents.agents
        }
        
        var selectedModel: Model
        var availableModels: [Model] {
            models.models
        }
        
        fileprivate let models: Models
        fileprivate let agents: Agents
        
        init(models: Models, agents: Agents) {
            self.models = models
            self.agents = agents
            self.selectedAgent = agents.default
            self.selectedModel = models.default
        }
    }
    
    enum Action: Equatable, Sendable {
        case selectNextAgent
        
        @CasePathable
        enum DelegateAction: Equatable, Sendable {
            case selectNewModel(Model)
        }

        @CasePathable
        enum InternalAction: Equatable, Sendable {
            case selectAgent(Agent)
            case selectModel(Model)
        }

        case `internal`(InternalAction)
        case delegate(DelegateAction)
    }
    
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .selectNextAgent:
                guard let index = state.availableAgents.firstIndex(where: { $0 == state.selectedAgent }) else { return .none }
                let nextIndex = (index + 1) % state.availableAgents.count
                state.selectedAgent = state.availableAgents[nextIndex]
                return .none
            case let .internal(.selectAgent(agent)):
                state.selectedAgent = agent
                return .none
            case let .internal(.selectModel(model)):
                state.selectedModel = model
                return .none
            case .delegate:
                return .none
            }
        }
    }
}

struct ContextAgentToolbarView: View {
    @Bindable var store: StoreOf<ContextAgentToolbarFeature>
    
    var body: some View {
        // Left side - Mode and Model selectors
        HStack(spacing: 8) {
            if store.availableAgents.count > 1 {
                Menu {
                    ForEach(store.availableAgents, id: \.self) { mode in
                        Button {
                            store.send(.internal(.selectAgent(mode)))
                        } label: {
                            HStack {
                                Text(mode.name)
                                if mode == store.selectedAgent {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        store.selectedAgent.icon
                            .font(.system(size: 12))
                        Text(store.selectedAgent.name)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .font(.system(size: 13, weight: .medium))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(store.selectedAgent.color)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(store.selectedAgent.color.opacity(0.15))
                    )
                }
                .buttonStyle(.plain)
            } else {
                HStack(spacing: 4) {
                    store.selectedAgent.icon
                        .font(.system(size: 12))
                    Text(store.selectedAgent.name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(store.selectedAgent.color)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(store.selectedAgent.color.opacity(0.15))
                )
            }

            HStack(spacing: 4) {
                Button {
                    store.send(.delegate(.selectNewModel(store.selectedModel)))
                } label: {
                    Text(store.selectedModel.displayName)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .font(.system(size: 13))
                    if store.availableModels.count > 1 {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                    }
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(.secondary)
        }
    }
}
