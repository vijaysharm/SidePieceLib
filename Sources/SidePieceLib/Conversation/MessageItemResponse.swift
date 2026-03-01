//
//  MessageItemResponse.swift
//  SidePiece
//

import ComposableArchitecture
import Textual
import SwiftUI

@Reducer
public struct MessageItemResponseFeature: Sendable {
    @ObservableState
    public struct State: Equatable, Sendable {
        let projectURL: URL
        var blocks: IdentifiedArrayOf<ResponseBlockFeature.State> = []
        var content: [ConversationItem] {
            blocks.content
        }
    }

    public enum Action: Equatable, Sendable {
        case appendTextDelta(String)
        case appendReasoningDelta(String)
        case toolCallStart(id: String, name: String)
        case toolCallDelta(id: String, args: String)
        case toolCallEnd(id: String, name: String, arguments: String)
        case streamFinished(usage: TokenUsage?, reason: FinishReason)

        case executeToolCallApproved(ToolCallBlockFeature.State)
        case requestToolInteraction(ToolCallBlockFeature.State, ToolInteraction)

        case blocks(IdentifiedActionOf<ResponseBlockFeature>)

        @CasePathable
        public enum DelegateAction: Equatable, Sendable {
            case toolInteractionResponse(ToolInteractionResponse, ToolCallBlockFeature.State)
            case executeToolCall(ToolCallBlockFeature.State)
            case streamEnded(TokenUsage?)
            case streamError
            case restartStream
        }

        @CasePathable
        public enum InternalAction: Equatable, Sendable {
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

    public var body: some ReducerOf<Self> {
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

                // Only process the first toolCallEnd for this tool — the OpenAI
                // provider can emit duplicates (function_call_arguments.done AND
                // output_item.done). Re-dispatching a tool that already left
                // .streaming causes state corruption and decode failures.
                guard tool.status == .streaming else { return .none }

                tool.name = name
                tool.arguments = arguments
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

                    let awaitingUser = activeTools.filter {
                        if case let .toolCall(data) = $0 {
                            return data.status.isAwaitingUser
                        }
                        return  false
                    }

                    guard awaitingUser.isEmpty else {
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

                // Merge user response into arguments if this was an interactive tool
                var finalArguments = toolCall.arguments
                if case let .awaitingUser(interaction) = toolCall.status {
                    if let userValue = Self.resolveUserValue(from: toolCall, interaction: interaction) {
                        finalArguments = interaction.mergeResponse(userValue, into: toolCall.arguments)
                    }
                }

                if let block = state.blocks[id: toolCall.id], case var .toolCall(data) = block {
                    data.status = .executing
                    state.blocks[id: toolCall.id] = .toolCall(data)
                    let name = toolCall.name
                    let arguments = finalArguments
                    effects.append(.run { [toolRegistryClient] send in
                        do {
                            let result = try await toolRegistryClient.execute(name, arguments, projectURL)
                            await send(.internal(.toolCallComplete(toolCall, .success(result))))
                        } catch {
                            await send(.internal(.toolCallComplete(toolCall, .failure(ToolExecutionError(from: error)))))
                        }
                    }.cancellable(id: CancelID.toolExecution(toolCall.id)))
                }

                if let nextTool = state.nextWaitingBlock {
                    effects.append(.send(.delegate(.executeToolCall(nextTool))))
                }

                return .merge(effects)

            case let .requestToolInteraction(toolCall, interaction):
                guard let tool = state.blocks[id: toolCall.id] else {
                    return .none
                }

                guard case var .toolCall(data) = tool else {
                    return .none
                }

                let hasAwaitingUser = state.blocks.contains { block in
                    if case let .toolCall(data) = block {
                        return data.status.isAwaitingUser
                    }
                    return false
                }

                data.status = hasAwaitingUser ? .waitingForPriorTool : .awaitingUser(interaction)
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
                    data.status = .failed(error)
                    data.result = error.errorDescription ?? "Tool execution failed"
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
                case .allowOnce, .allowAlways, .input:
                    return .concatenate([
                        .send(.delegate(.toolInteractionResponse(response, data))),
                        .send(.executeToolCallApproved(data))
                    ])

                case .deny:
                    data.status = .denied
                    state.blocks[id: id] = .toolCall(data)

                    var effects: [Effect<Action>] = [
                        .send(.delegate(.toolInteractionResponse(response, data)))
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

    /// Extracts the user's response value from the tool call state based on the interaction type.
    /// Returns `nil` for permission/confirmation (no user data to merge).
    static func resolveUserValue(from toolCall: ToolCallBlockFeature.State, interaction: ToolInteraction) -> String? {
        switch interaction {
        case .questionnaire:
            return toolCall.questionnaire.encodedJSON
        case .textInput:
            let trimmed = toolCall.userInputText.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case .choice:
            return toolCall.userSelectedOption
        case .permission, .confirmation:
            return nil
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
                    let denialObject: [String: Any] = [
                        "error": "User denied permission to execute '\(data.name)'",
                        "denied": true
                    ]
                    if let jsonData = try? JSONSerialization.data(withJSONObject: denialObject),
                       let json = String(data: jsonData, encoding: .utf8) {
                        items.append(.toolResult(
                            id: data.toolCallId,
                            output: json
                        ))
                    }
                } else if case .failed(let error) = data.status {
                    let errorObject: [String: Any] = ["error": error.errorDescription ?? "Tool execution failed"]
                    if let jsonData = try? JSONSerialization.data(withJSONObject: errorObject),
                       let json = String(data: jsonData, encoding: .utf8) {
                        items.append(.toolResult(
                            id: data.toolCallId,
                            output: json
                        ))
                    }
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
