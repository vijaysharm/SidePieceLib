//
//  MessageItem.swift
//  SidePiece
//

import ComposableArchitecture
import SwiftUI

@Reducer
public struct MessageItemFeature: Sendable {
    @ObservableState
    public struct State: Equatable, Identifiable {
        public var id = UUID()
        let projectURL: URL
        var prompt: ContextInputFeature.State
        var history: [ConversationItem]
        var response: MessageItemResponseFeature.State
        
        /// The content parts from the user's input (images + text)
        var content: [ConversationItem] {
            [
                .message(
                    role: .user,
                    // TODO: The content can be duplicated files from the prompt and input field
                    content: prompt.images.content + prompt.inputField.content
                )
            ] + response.content
        }
    }

    public enum Action: Equatable {
        case startLLMStream
        case cancelLLMStream

        case prompt(ContextInputFeature.Action)
        case response(MessageItemResponseFeature.Action)
        
        case `internal`(InternalAction)
        case delegate(DelegateAction)

        @CasePathable
        public enum InternalAction: Equatable {
            case startLLMStream
            case llmEvent(LLMStreamEvent)
        }
        
        @CasePathable
        public enum DelegateAction: Equatable {
            case streamError(StreamingError)
        }
    }

    enum CancelID {
        case llmStream
    }
    
    @Dependency(\.messageItemClient) var messageItemClient
    
    public var body: some ReducerOf<Self> {
        Scope(state: \.prompt, action: \.prompt) {
            ContextInputFeature()
        }
        Scope(state: \.response, action: \.response) {
            MessageItemResponseFeature()
        }
        Reduce { state, action in
            switch action {
            case .startLLMStream:
                state.response.blocks = []
                return .send(.internal(.startLLMStream))

            case .cancelLLMStream:
                return .cancel(id: CancelID.llmStream)
                
            case .internal(.startLLMStream):
                let agent = state.prompt.agentToolbar.selectedAgent
                let model = state.prompt.agentToolbar.selectedModel
                let history = state.history + state.content
                let context = MessageItemClient.PromptContext(model: model, agent: agent, projectURL: state.projectURL)

                return .run { [history, context] send in
                    do {
                        let systemPrompt = try await messageItemClient.systemPrompt(context)
                        let options = LLMRequestOptions(
                            agent: agent,
                            systemPrompt: systemPrompt,
                            temperature: nil, // TODO: Should this come from the model? model.supportsTemperature ? 0 : nil,
                            maxOutputTokens: nil, // TODO: Should this come from the model?
                            tools: agent.tools.map(\.definition)
                        )
                        for try await event in model.stream(history, options) {
                            await send(.internal(.llmEvent(event)))
                        }
                    } catch {
                        await send(.delegate(.streamError(StreamingError(from: error))))
                    }
                }
                
                .cancellable(id: CancelID.llmStream, cancelInFlight: true)
                
            case let .internal(.llmEvent(event)):
                switch event {
                case let .textDelta(text):
                    return .send(.response(.appendTextDelta(text)))
                    
                case let .toolCallStart(id, name):
                    return .send(.response(.toolCallStart(id: id, name: name)))
                    
                case let .toolCallDelta(id, args):
                    return .send(.response(.toolCallDelta(id: id, args: args)))
                    
                case let .toolCallEnd(toolId, name, arguments):
                    return .send(.response(.toolCallEnd(id: toolId, name: name, arguments: arguments)))
                    
                case let .reasoningDelta(text):
                    return .send(.response(.appendReasoningDelta(text)))
                    
                case let .finished(usage, reason):
                    return .send(.response(.streamFinished(usage: usage, reason: reason)))
                }

            case .response(.delegate(.restartStream)):
                return .send(.internal(.startLLMStream))

            case .response:
                return .none

            case .prompt:
                return .none

            case .internal:
                return .none

            case .delegate:
                return .none
            }
        }
    }
}

struct MessageItemView: View {
    @Bindable var store: StoreOf<MessageItemFeature>
    var isStreaming: Bool = false
    var tokenUsage: TokenUsage

    var body: some View {
        Section {
            MessageItemResponseView(
                store: store.scope(state: \.response, action: \.response)
            )
            .listRowSeparator(.hidden)
        } header: {
            MessageHeaderView(
                store: store,
                isStreaming: isStreaming,
                tokenUsage: tokenUsage
            )
        }
        .id(store.id)
    }
}

// MARK: - Message Header (Sticky)

private struct MessageHeaderView: View {
    @Bindable var store: StoreOf<MessageItemFeature>
    var isStreaming: Bool = false
    var tokenUsage: TokenUsage
    
    var body: some View {
        ContextInputView(
            store: store.scope(
                state: \.prompt,
                action: \.prompt
            ),
            isStreaming: isStreaming,
            tokenUsage: tokenUsage
        )
        .background(Color(NSColor.windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
