//
//  Messages.swift
//  SidePiece

import ComposableArchitecture
import SwiftUI

@Reducer
struct MessagesFeature {
    @ObservableState
    struct State: Equatable {
        var title = MessageTitleFeature.State()
        var date: Date
        var model: Model
        var projectURL: URL = URL(fileURLWithPath: "/")
        var messageItems: IdentifiedArrayOf<MessageItemFeature.State> = []
        var streamingMessageID: UUID? = nil

        /// Tools that have been "always allowed" (by name) - shared across all messages
        var allowedTools: Set<String> = []
    }

    enum Action: Equatable {
        case title(MessageTitleFeature.Action)
        case messageItems(IdentifiedActionOf<MessageItemFeature>)
        
        /// Start streaming for a message (builds history from previous messages and delegates to MessageItemFeature)
        case startStreaming(ContextInputFeature.State)
        case restartStreaming(UUID)
        
        /// Stop streaming for a message
        case stopStreaming(UUID)
    }

    @Dependency(\.uuid) var uuid
    
    var body: some ReducerOf<Self> {
        Scope(state: \.title, action: \.title) {
            MessageTitleFeature()
        }
        Reduce { state, action in
            switch action {
            case let .startStreaming(input):
                let history = state.messageItems.flatMap { message in
                    message.content
                }
                let message = MessageItemFeature.State(
                    id: uuid(),
                    projectURL: state.projectURL,
                    prompt: input,
                    history: history,
                    response: MessageItemResponseFeature.State(
                        projectURL: state.projectURL
                    )
                )

                state.messageItems.append(message)
                state.streamingMessageID = message.id

                return .send(.messageItems(.element(id: message.id, action: .startLLMStream)))
                
            // Called by Conversation Feature
            case let .restartStreaming(id):
                guard var message = state.messageItems[id: id] else { return .none }
                message.history = state.messageItems
                    .filter { $0.id != message.id }
                    .flatMap { message in
                        message.content
                    }
                state.messageItems[id: id] = message
                state.streamingMessageID = message.id

                // Delegate to MessageItemFeature
                return .send(.messageItems(.element(id: message.id, action: .startLLMStream)))

            case let .stopStreaming(id):
                state.streamingMessageID = nil
                return .send(.messageItems(.element(id: id, action: .cancelLLMStream)))

            case let .messageItems(.element(id, action: .prompt(.agentToolbar(.internal(.selectModel(model)))))):
                guard id == state.messageItems.first?.id else { return .none }
                state.model = model
                return .none

            case let .messageItems(.element(id, action: .response(.delegate(.streamEnded)))),
                    let .messageItems(.element(id, action: .response(.delegate(.streamError)))):
                state.streamingMessageID = nil
                
                guard let message = state.messageItems[id: id] else { return .none }
                // TODO: Choose the cheapest model. not the sasme one as the prompt (maybe a free one from the same family)
                let model = message.prompt.agentToolbar.selectedModel
                // Limit the amount of context needed to get the title
                let history = message.content.compactMap { item -> ConversationItem? in
                    switch item {
                    case let .message(role, content) where role == .user || role == .assistant:
                        let textOnly = content.filter {
                            if case .text = $0 { return true }
                            return false
                        }
                        return textOnly.isEmpty ? nil : .message(role: role, content: textOnly)
                    default:
                        return nil
                    }
                }
                
                return .send(.title(.stream(model, history)))

            case let .messageItems(.element(id, action: .response(.delegate(.executeToolCall(toolCall))))):
                if state.allowedTools.contains(toolCall.name) {
                    return .send(.messageItems(.element(id: id, action: .response(.executeToolCallApproved(toolCall)))))
                }

                return .send(.messageItems(.element(id: id, action: .response(.requestToolPermission(toolCall)))))

            case let .messageItems(.element(_, action: .response(.delegate(.toolPermissionResponse(.allowAlways, tool))))):
                // Intercept allowAlways to update conversation-level state
                state.allowedTools.insert(tool.name)
                return .none

            case .title:
                return .none

            case .messageItems:
                return .none
            }
        }
        .forEach(\.messageItems, action: \.messageItems) {
            MessageItemFeature()
        }
    }
}

extension MessagesFeature.State {
    var relativeTimestamp: String {
        @Dependency(\.date) var date
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(
            for: self.date,
            relativeTo: date()
        )
    }
}

// MARK: - Views

struct MessagesView: View {
    @Bindable var store: StoreOf<MessagesFeature>
    var isStreaming: Bool = false
    var tokenUsage: TokenUsage

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                MessageTitleView(store: store.scope(state: \.title, action: \.title))
                
                HStack(spacing: 6) {
                    Text("\(store.relativeTimestamp)")
                        .foregroundStyle(.secondary)
                    
                    Text("·")
                        .foregroundStyle(.tertiary)
                    
                    Text("\(store.model.displayName)")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.system(size: 13, weight: .medium))
            .padding(.bottom)
            .padding(.horizontal, 8)

            // TODO: I have to use a List here because when a LazyVStack with
            // TODO: a ScrollView is used, it lead to an issue where the main
            // TODO: thread would lock up. My guess is it was something under
            // TODO: the hood, but I never got to the root cause
            List {
                ForEachStore(
                  store.scope(state: \.messageItems, action: \.messageItems)
                ) { store in
                    MessageItemView(
                        store: store,
                        isStreaming: isStreaming,
                        tokenUsage: tokenUsage
                    )
                }
            }
            .listStyle(.plain)
        }
    }
}

#Preview {
    SidePieceView()
        .frame(width: 900, height: 500)
}
