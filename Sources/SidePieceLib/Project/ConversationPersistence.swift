//
//  ConversationPersistence.swift
//  SidePiece
//

import ComposableArchitecture
import Foundation

@Reducer
public struct ConversationPersistenceFeature: Sendable {
    @Dependency(\.mainQueue) var mainQueue
    @Dependency(\.conversationStorageClient) var conversationStorageClient
    
    enum CancelID: Hashable {
        case draftSave(UUID)
    }

    public var body: some ReducerOf<ProjectFeature> {
        Reduce { state, action in
            switch action {
            // Stream completed
            case let .conversations(.element(id: id, action: .messages(.messageItems(.element(_, .response(.delegate(.streamEnded))))))):
                return .send(.internal(.saveConversation(id)))

            // Stream errored (save partial)
            case let .conversations(.element(id: id, action: .messages(.messageItems(.element(_, .response(.delegate(.streamError))))))):
                return .send(.internal(.saveConversation(id)))

            // Title generated
            case let .conversations(.element(id: id, action: .messages(.title(.internal(.llmEvent(.finished)))))):
                return .send(.internal(.saveConversation(id)))

            // Title renamed
            case let .conversations(.element(id: id, action: .messages(.title(.rename(_))))):
                return .send(.internal(.saveConversation(id)))

            // Draft auto-save: debounced on text changes
            case let .conversations(.element(id: id, action: .mainTextView(.inputField))):
                guard state.conversations[id: id]?.messages == nil else { return .none }
                return .send(.internal(.saveDraft(id)))
                    .debounce(id: CancelID.draftSave(id), for: .milliseconds(500), scheduler: mainQueue)
            
            case let .internal(.saveConversation(conversationID)):
                guard let conversation = state.conversations[id: conversationID] else { return .none }
                // Don't save empty conversations
                guard !conversation.isEmpty else { return .none }
                let dto = conversation.toDTO()
                let indexEntry = conversation.toIndexEntry()
                let projectURL = conversation.project
                return .run { [conversationStorageClient] _ in
                    try? await conversationStorageClient.save(dto, indexEntry, projectURL)
                }

            case let .internal(.saveDraft(conversationID)):
                guard let conversation = state.conversations[id: conversationID] else { return .none }
                guard conversation.isDraft else { return .none }
                let dto = conversation.toDTO()
                let indexEntry = conversation.toIndexEntry()
                let projectURL = conversation.project
                return .run { [conversationStorageClient] _ in
                    try? await conversationStorageClient.save(dto, indexEntry, projectURL)
                }
            default:
                return .none
            }
        }
    }
}
