//
//  MessageItemResponse.swift
//  SidePiece
//

import ComposableArchitecture
import Textual
import SwiftUI

@Reducer
struct MessageItemResponseFeature: Sendable {
    @ObservableState
    struct State: Equatable, Sendable {
        let projectURL: URL
        var blocks: IdentifiedArrayOf<ResponseBlockFeature.State> = []
        var content: [ConversationItem] {
            blocks.content
        }
    }

    enum Action: Equatable, Sendable {
        case appendTextDelta(String)
        case appendReasoningDelta(String)
        case toolCallStart(id: String, name: String)
        case toolCallDelta(id: String, args: String)
        case toolCallEnd(id: String, name: String, arguments: String)
        case streamFinished(usage: TokenUsage?, reason: FinishReason)

        case executeToolCallApproved(ToolCallBlockFeature.State)
        case requestToolPermission(ToolCallBlockFeature.State)

        case blocks(IdentifiedActionOf<ResponseBlockFeature>)
        
        @CasePathable
        enum DelegateAction: Equatable, Sendable {
            case toolPermissionResponse(ToolPermissionDecision, ToolCallBlockFeature.State)
            case executeToolCall(ToolCallBlockFeature.State)
            case streamEnded(TokenUsage?)
            case streamError
            case restartStream
        }

        @CasePathable
        enum InternalAction: Equatable, Sendable {
            case toolCallComplete(ToolCallBlockFeature.State, Result<String, ToolExecutionError>)
        }

        case `internal`(InternalAction)
        case delegate(DelegateAction)
    }
    
    enum CancelID: Hashable {
        case toolExecution(UUID)
    }
    
    @Dependency(\.uuid) var uuid
    @Dependency(\.toolRegistryClient) var toolRegistryClient

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .appendTextDelta(text):
                if var block = state.lastStreamingTextBlock {
                    block.content += text
                    state.blocks[id: block.id] = .text(block)
                } else {
                    state.blocks.append(.text(TextBlockFeature.State(
                        id: uuid(),
                        content: text,
                        isStreaming: true
                    )))
                }
                return .none
                
            case let .appendReasoningDelta(text):
                if var block = state.lastStreamingReasoningBlock {
                    block.content += text
                    state.blocks[id: block.id] = .reasoning(block)
                } else {
                    state.blocks.append(.reasoning(ReasoningBlockFeature.State(
                        id: uuid(),
                        content: text,
                        isStreaming: true,
                        isExpanded: false
                    )))
                }
                return .none
                
            case let .toolCallStart(id, name):
                state.blocks.append(.toolCall(ToolCallBlockFeature.State(
                    id: uuid(),
                    toolCallId: id,
                    name: name,
                    arguments: "",
                    status: .streaming
                )))
                return .none
                
            case let .toolCallDelta(id, args):
                guard var tool = state.toolCallWith(id: id) else {
                    return .none
                }
                tool.arguments += args
                state.blocks[id: tool.id] = .toolCall(tool)
                
                return .none
                
            case let .toolCallEnd(id, name, arguments):
                var tool = state.toolCallWith(id: id) ?? ToolCallBlockFeature.State(
                    id: uuid(),
                    toolCallId: id,
                    name: name,
                    arguments: arguments,
                    status: .streaming
                )
                
                tool.name = name
                tool.arguments = arguments
                tool.status = .streaming
                state.blocks[id: tool.id] = .toolCall(tool)
                
                return .send(.delegate(.executeToolCall(tool)))
                
            case let .streamFinished(usage, reason):
                for block in state.blocks {
                    switch block {
                    case var .text(data) where data.isStreaming:
                        data.isStreaming = false
                        state.blocks[id: data.id] = .text(data)
                    case var .reasoning(data) where data.isStreaming:
                        data.isStreaming = false
                        state.blocks[id: data.id] = .reasoning(data)
                    default:
                        break
                    }
                }
                
                switch reason {
                case .stop, .length, .unknown, .contentFilter:
                    return .send(.delegate(.streamEnded(usage)))
                
                case let .error(error):
                    state.blocks.append(.error(ErrorBlockFeature.State(
                        id: uuid(),
                        error: error
                    )))
                    // TODO: Should any tools that are active be cancelled?
                    return .send(.delegate(.streamError))
                
                case .toolCalls:
                    let allTools = state.blocks.filter {
                        if case .toolCall = $0 {
                            return true
                        }
                        return  false
                    }
                    
                    guard !allTools.isEmpty else {
                        return .send(.delegate(.streamEnded(usage)))
                    }
                    
                    // We have tools, will check if they're active

                    let activeTools = allTools.filter {
                        if case let .toolCall(data) = $0 {
                            return data.status.isActive
                        }
                        return  false
                    }
                    
                    guard !activeTools.isEmpty else {
                        return .send(.delegate(.restartStream))
                    }
                    
                    let pendingUserApproval = activeTools.filter {
                        if case let .toolCall(data) = $0 {
                            return data.status == .pendingPermission
                        }
                        return  false
                    }
                    
                    guard pendingUserApproval.isEmpty else {
                        return .send(.delegate(.streamEnded(usage)))
                    }
                    
                    guard let waitingForTools = activeTools.first(where: {
                        if case let .toolCall(data) = $0 {
                            return data.status == .waitingForPriorTool
                        }
                        return  false
                    }) else {
                        // of all the active tools, they're all still executing
                        return .none
                    }
                    
                    guard case let .toolCall(data) = waitingForTools else {
                        return .none
                    }
                    
                    // Let's promote the first tool in this state and
                    // kick start the approval flow
                    return .send(.delegate(.executeToolCall(data)))
                }
                
            case let .executeToolCallApproved(toolCall):
                var effects: [Effect<Action>] = []
                let projectURL = state.projectURL
                if let block = state.blocks[id: toolCall.id], case var .toolCall(data) = block {
                    data.status = .executing
                    state.blocks[id: toolCall.id] = .toolCall(data)
                    effects.append(.run { [toolRegistryClient] send in
                        do {
                            let result = try await toolRegistryClient.execute(toolCall.name, toolCall.arguments, projectURL)
                            await send(.internal(.toolCallComplete(toolCall, .success(result))))
                        } catch {
                            await send(.internal(.toolCallComplete(toolCall, .failure(.unknown("\(error)")))))
                        }
                    }.cancellable(id: CancelID.toolExecution(toolCall.id)))
                }
                    
                if let nextTool = state.nextWaitingBlock {
                    effects.append(.send(.delegate(.executeToolCall(nextTool))))
                }

                return .merge(effects)

            case let .requestToolPermission(toolCall):
                guard let tool = state.blocks[id: toolCall.id] else {
                    return .none
                }
                
                guard case var .toolCall(data) = tool else {
                    return .none
                }
                
                let hasPendingPermission = state.blocks.contains { block in
                    if case let .toolCall(data) = block {
                        return data.status == .pendingPermission
                    }
                    return false
                }
                
                data.status = hasPendingPermission ? .waitingForPriorTool : .pendingPermission
                state.blocks[id: data.id] = .toolCall(data)

                return .none
                
            case let .internal(.toolCallComplete(tool, response)):
                guard let block = state.blocks[id: tool.id], case var .toolCall(data) = block else {
                    return .none
                }
                
                switch response {
                case let .success(result):
                    data.status = .completed
                    data.result = result
                case let .failure(error):
                    switch error {
                    case let .unknown(error):
                        data.status = .failed("\(error)")
                        data.result = error
                    }
                }
                
                state.blocks[id: tool.id] = .toolCall(data)
                
                let activeTools = state.blocks.filter {
                    if case let .toolCall(data) = $0 {
                        return data.status.isActive
                    }
                    return  false
                }
                
                guard activeTools.isEmpty else {
                    return .none
                }
                
                return .send(.delegate(.restartStream))
                
            case let .blocks(.element(id: id, action: .toolCall(.delegate(.response(response))))):
                guard let tool = state.blocks[id: id] else {
                    return .none
                }
                
                guard case var .toolCall(data) = tool else {
                    return .none
                }
                
                switch response {
                case .allowOnce, .allowAlways:
                    return .concatenate([
                        .send(.delegate(.toolPermissionResponse(response, data))),
                        .send(.executeToolCallApproved(data))
                    ])

                case .deny:
                    data.status = .denied
                    state.blocks[id: id] = .toolCall(data)
                    
                    var effects: [Effect<Action>] = [
                        .send(.delegate(.toolPermissionResponse(response, data)))
                    ]
                    if let nextTool = state.nextWaitingBlock {
                        effects.append(.send(.delegate(.executeToolCall(nextTool))))
                    }
                    
                    return .concatenate(effects)
                }

            case .blocks:
                return .none

            case .delegate:
                return .none
            }
        }
        .forEach(\.blocks, action: \.blocks) {
            ResponseBlockFeature()
        }
    }

}

extension MessageItemResponseFeature.State {
    var nextWaitingBlock: ToolCallBlockFeature.State? {
        // Find first tool in waitingForPriorTool state
        let waitingBlock = blocks.first(where: { block in
            if case let .toolCall(data) = block {
                return data.status == .waitingForPriorTool
            }
            return false
        })
        
        guard let waitingBlock else { return nil }
        guard case let .toolCall(data) = waitingBlock else { return nil }
            
        return data
    }

    var lastStreamingTextBlock: TextBlockFeature.State? {
        for block in blocks.reversed() {
            if case let .text(data) = block, data.isStreaming {
                return data
            }
        }
        return nil
    }
    
    var lastStreamingReasoningBlock: ReasoningBlockFeature.State? {
        for block in blocks.reversed() {
            if case let .reasoning(data) = block, data.isStreaming {
                return data
            }
        }
        return nil
    }
    
    func toolCallWith(id toolId: String) -> ToolCallBlockFeature.State? {
        for block in blocks.reversed() {
            if case let .toolCall(data) = block, data.toolCallId == toolId {
                return data
            }
        }
        return nil
    }
}

extension IdentifiedArrayOf where Element == ResponseBlockFeature.State {
    var content: [ConversationItem] {
        var items: [ConversationItem] = []
        var accumulatedText = ""

        for block in self {
            switch block {
            case let .text(data):
                accumulatedText += data.content

            case .reasoning:
                // Reasoning is not sent to the model
                break

            case let .toolCall(data):
                // Flush accumulated text as assistant message before tool calls
                if !accumulatedText.isEmpty {
                    items.append(.message(
                        role: .assistant,
                        content: [.text(accumulatedText)]
                    ))
                    accumulatedText = ""
                }

                // Add tool call
                items.append(.toolCall(
                    id: data.toolCallId,
                    name: data.name,
                    arguments: data.arguments
                ))

                // Add tool result if completed
                if case .completed = data.status, let result = data.result {
                    items.append(.toolResult(
                        id: data.toolCallId,
                        output: result
                    ))
                } else if case .denied = data.status {
                    let denialResult = """
                    {"error": "User denied permission to execute '\(data.name)'", "denied": true}
                    """
                    items.append(.toolResult(
                        id: data.toolCallId,
                        output: denialResult
                    ))
                } else if case .failed(let errorMsg) = data.status {
                    let failedResult = """
                    {"error": "\(errorMsg)"}
                    """
                    items.append(.toolResult(
                        id: data.toolCallId,
                        output: failedResult
                    ))
                }

            case .error:
                // Errors are not sent to the model
                break
            }
        }

        // Flush any remaining text
        if !accumulatedText.isEmpty {
            items.append(.message(
                role: .assistant,
                content: [.text(accumulatedText)]
            ))
        }

        return items
    }
}

// MARK: - View

struct MessageItemResponseView: View {
    @Bindable var store: StoreOf<MessageItemResponseFeature>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEachStore(
              store.scope(state: \.blocks, action: \.blocks)
            ) { store in
                switch store.state {
                case .text:
                    if let store = store.scope(state: \.text, action: \.text) {
                        TextBlockView(store: store)
                    }
                case .toolCall:
                    if let store = store.scope(state: \.toolCall, action: \.toolCall) {
                        ToolCallBlockView(store: store)
                    }
                case .reasoning:
                    if let store = store.scope(state: \.reasoning, action: \.reasoning) {
                        ReasoningBlockView(store: store)
                    }
                case .error:
                    if let store = store.scope(state: \.error, action: \.error) {
                        ErrorBlockView(store: store)
                    }
                }
            }
        }
        .padding(.bottom, 32)
    }
}

#Preview {
    SidePieceView()
        .frame(width: 900, height: 500)
}
