//
//  ToolCallBlock.swift
//  SidePiece
//

import ComposableArchitecture
import SwiftUI

// MARK: - Tool Interaction Types

/// Describes what interaction a tool requires from the user before execution.
/// Permission is the default — a simple Allow/Deny gate. Other types collect
/// richer input from the user (confirmation messages, free-form text, choices).
public enum ToolInteraction: Equatable, Sendable {
    /// Simple approval gate. User sees Allow/Deny. (Default for all tools.)
    case permission

    /// Confirmation with a descriptive message. User sees Confirm/Deny.
    case confirmation(message: String)

    /// Free-form text input. User enters a string value before the tool runs.
    case textInput(prompt: String, placeholder: String?)

    /// Single choice from a list of options.
    case choice(prompt: String, options: [String])

    /// Whether this interaction type supports "Allow Always" (skipping future interactions).
    /// Text input and choice always require the user to respond, so "Always" is not offered.
    var supportsAlwaysAllow: Bool {
        switch self {
        case .permission, .confirmation: true
        case .textInput, .choice: false
        }
    }
}

/// The user's response to a tool interaction. Unifies the old permission
/// decision (Allow Once / Allow Always / Deny) with richer response types.
public enum ToolInteractionResponse: Equatable, Sendable {
    /// User approved execution (for `.permission` and `.confirmation`).
    case allowOnce
    /// User approved execution and wants to skip future interactions for this tool.
    case allowAlways
    /// User denied execution.
    case deny
    /// User provided a value (for `.textInput` and `.choice`).
    case input(String)

    /// Whether this response permits tool execution.
    var isApproval: Bool {
        switch self {
        case .allowOnce, .allowAlways, .input: true
        case .deny: false
        }
    }
}

// MARK: - Tool Call Status

public enum ToolCallStatus: Equatable, Sendable {
    case streaming              // Arguments still arriving
    case waitingForPriorTool    // Waiting for earlier tool to complete its interaction
    case awaitingUser(ToolInteraction) // Waiting for user interaction
    case denied                 // User denied execution

    case executing              // Tool is running
    case completed              // Finished successfully
    case failed(String)         // Execution failed with error message

    var isActive: Bool {
        switch self {
        case .streaming, .waitingForPriorTool, .awaitingUser, .executing:
            true
        case .completed, .denied, .failed:
            false
        }
    }

    var isAwaitingUser: Bool {
        if case .awaitingUser = self { return true }
        return false
    }
}

public enum ToolExecutionError: LocalizedError, Equatable {
    case unknown(String)
}

public enum AllowAction: String, CaseIterable, Equatable, Sendable {
    case allowOnce = "Allow Once"
    case allowAlways = "Allow Always"
}

// MARK: - Feature

@Reducer
public struct ToolCallBlockFeature: Sendable {
    @ObservableState
    public struct State: Identifiable, Equatable, Sendable {
        public let id: UUID
        let toolCallId: String
        var name: String
        var arguments: String
        var status: ToolCallStatus
        var result: String?
        var isExpanded: Bool = false
        var selectedAllowAction: AllowAction = .allowAlways

        // User-provided response value for interactive tools (.textInput, .choice)
        var userInputText: String = ""
        var userSelectedOption: String?
    }

    public enum Action: Equatable, Sendable {
        @CasePathable
        public enum DelegateAction: Equatable, Sendable {
            case response(ToolInteractionResponse)
        }

        @CasePathable
        public enum InternalAction: Equatable, Sendable {
            case toggleExpanded
            case setAllowAction(AllowAction)
            case setUserInputText(String)
            case setUserSelectedOption(String)
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
            case let .internal(.setAllowAction(action)):
                state.selectedAllowAction = action
                return .none
            case let .internal(.setUserInputText(text)):
                state.userInputText = text
                return .none
            case let .internal(.setUserSelectedOption(option)):
                state.userSelectedOption = option
                return .none
            case .internal, .delegate:
                return .none
            }
        }
    }
}

// MARK: - View

struct ToolCallBlockView: View {
    @Bindable var store: StoreOf<ToolCallBlockFeature>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header row with tool name, chevron, and interaction controls
            HStack(spacing: 8) {
                // Left side: expand button with tool name + chevron
                Button {
                    store.send(.internal(.toggleExpanded), animation: .easeInOut(duration: 0.2))
                } label: {
                    HStack(spacing: 8) {
                        Text(store.name)
                            .foregroundStyle(.secondary)

                        if isActive {
                            ProgressView()
                                .controlSize(.mini)
                        }

                        if case .waitingForPriorTool = store.status {
                            Text("Queued")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }

                        if case .denied = store.status {
                            Text("Denied")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }

                        if case .failed = store.status {
                            Text("Failed")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }

                        Image(systemName: store.isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                // Right side: interaction controls (only when awaiting user)
                if case let .awaitingUser(interaction) = store.status {
                    switch interaction {
                    case .permission, .confirmation:
                        PermissionControls(
                            selectedAction: store.selectedAllowAction,
                            showAlwaysOption: interaction.supportsAlwaysAllow,
                            onDeny: {
                                store.send(.delegate(.response(.deny)))
                            },
                            onAllow: { selection in
                                store.send(.delegate(.response(selection)))
                            },
                            onSelectAction: { action in
                                store.send(.internal(.setAllowAction(action)))
                            }
                        )

                    case .textInput, .choice:
                        // Submit / Cancel for input-based interactions
                        InputControls(
                            onCancel: {
                                store.send(.delegate(.response(.deny)))
                            },
                            onSubmit: {
                                if case .textInput = interaction {
                                    store.send(.delegate(.response(.input(store.userInputText))))
                                } else if let selected = store.userSelectedOption {
                                    store.send(.delegate(.response(.input(selected))))
                                }
                            },
                            isSubmitDisabled: {
                                if case .textInput = interaction {
                                    return store.userInputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                } else {
                                    return store.userSelectedOption == nil
                                }
                            }()
                        )
                    }
                }
            }
            .animation(nil, value: store.isExpanded)

            // Interaction-specific content below the header
            if case let .awaitingUser(interaction) = store.status {
                switch interaction {
                case .permission:
                    EmptyView()

                case let .confirmation(message):
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 16)

                case let .textInput(prompt, placeholder):
                    VStack(alignment: .leading, spacing: 4) {
                        Text(prompt)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)

                        TextField(
                            placeholder ?? "",
                            text: Binding(
                                get: { store.userInputText },
                                set: { store.send(.internal(.setUserInputText($0))) }
                            )
                        )
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                        .onSubmit {
                            let trimmed = store.userInputText.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !trimmed.isEmpty {
                                store.send(.delegate(.response(.input(store.userInputText))))
                            }
                        }
                    }
                    .padding(.leading, 16)

                case let .choice(prompt, options):
                    VStack(alignment: .leading, spacing: 4) {
                        Text(prompt)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)

                        ForEach(options, id: \.self) { option in
                            Button {
                                store.send(.internal(.setUserSelectedOption(option)))
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: store.userSelectedOption == option ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 12))
                                    Text(option)
                                        .font(.system(size: 12, design: .monospaced))
                                }
                                .foregroundStyle(store.userSelectedOption == option ? .primary : .secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.leading, 16)
                }
            }

            // Expanded content (arguments + result)
            if store.isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    if !store.arguments.isEmpty {
                        Text(formatJSON(store.arguments))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .textSelection(.enabled)
                    }

                    if let result = store.result {
                        Text(formatJSON(result))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .textSelection(.enabled)
                    }
                }
                .padding(.leading, 16)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var isActive: Bool {
        if case .streaming = store.status { return true }
        if case .executing = store.status { return true }
        return false
    }

    private func formatJSON(_ json: String) -> String {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let prettyData = try? JSONSerialization.data(withJSONObject: object, options: .prettyPrinted),
              let prettyString = String(data: prettyData, encoding: .utf8) else {
            return json
        }
        return prettyString
    }
}

// MARK: - Interaction Controls

fileprivate struct PermissionControls: View {
    let selectedAction: AllowAction
    let showAlwaysOption: Bool
    let onDeny: () -> Void
    let onAllow: (ToolInteractionResponse) -> Void
    let onSelectAction: (AllowAction) -> Void

    var body: some View {
        HStack(spacing: 16) {
            // Deny - plain text button
            Button(action: onDeny) {
                Text("Deny")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            // Allow split button with dropdown
            if showAlwaysOption {
                AllowSplitButton(
                    selectedAction: selectedAction,
                    onAllow: onAllow,
                    onSelectAction: onSelectAction
                )
            } else {
                Button {
                    onAllow(.allowOnce)
                } label: {
                    Text("Allow")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(0.1))
                .cornerRadius(6)
            }
        }
    }
}

fileprivate struct InputControls: View {
    let onCancel: () -> Void
    let onSubmit: () -> Void
    let isSubmitDisabled: Bool

    var body: some View {
        HStack(spacing: 16) {
            Button(action: onCancel) {
                Text("Cancel")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            Button(action: onSubmit) {
                Text("Submit")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
            .disabled(isSubmitDisabled)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(isSubmitDisabled ? 0.05 : 0.1))
            .cornerRadius(6)
        }
    }
}

fileprivate struct AllowSplitButton: View {
    let selectedAction: AllowAction
    let onAllow: (ToolInteractionResponse) -> Void
    let onSelectAction: (AllowAction) -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button {
                switch selectedAction {
                case .allowOnce:
                    onAllow(.allowOnce)
                case .allowAlways:
                    onAllow(.allowAlways)
                }
            } label: {
                Text(selectedAction.rawValue)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)

            Menu {
                ForEach(AllowAction.allCases, id: \.self) { action in
                    Button {
                        onSelectAction(action)
                    } label: {
                        if action == selectedAction {
                            Label(action.rawValue, systemImage: "checkmark")
                        } else {
                            Text(action.rawValue)
                        }
                    }
                }
            } label: {
                Text("")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 16)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.1))
        .cornerRadius(6)
    }
}

#Preview {
    ScrollView {
        VStack(alignment: .leading, spacing: 16) {
            ToolCallBlockView(store: Store(initialState: ToolCallBlockFeature.State(
                id: UUID(),
                toolCallId: "read_file",
                name: "read_file",
                arguments: "{\"path\": \"/Users/test/file.txt\"}",
                status: .streaming
            )) {
                ToolCallBlockFeature()
            })

            // Waiting for prior tool
            ToolCallBlockView(store: Store(initialState: ToolCallBlockFeature.State(
                id: UUID(),
                toolCallId: "read_file",
                name: "read_file",
                arguments: "{\"path\": \"/Users/test/file.txt\"}",
                status: .waitingForPriorTool
            )) {
                ToolCallBlockFeature()
            })

            // Permission interaction (was pendingPermission)
            ToolCallBlockView(store: Store(initialState: ToolCallBlockFeature.State(
                id: UUID(),
                toolCallId: "read_file",
                name: "read_file",
                arguments: "{\"path\": \"/Users/test/file.txt\"}",
                status: .awaitingUser(.permission)
            )) {
                ToolCallBlockFeature()
            })

            // Confirmation interaction
            ToolCallBlockView(store: Store(initialState: ToolCallBlockFeature.State(
                id: UUID(),
                toolCallId: "delete_file",
                name: "delete_file",
                arguments: "{\"path\": \"/Users/test/important.txt\"}",
                status: .awaitingUser(.confirmation(message: "This will permanently delete important.txt"))
            )) {
                ToolCallBlockFeature()
            })

            // Text input interaction
            ToolCallBlockView(store: Store(initialState: ToolCallBlockFeature.State(
                id: UUID(),
                toolCallId: "git_commit",
                name: "git_commit",
                arguments: "{\"files\": [\"main.swift\"]}",
                status: .awaitingUser(.textInput(prompt: "Enter commit message:", placeholder: "feat: ..."))
            )) {
                ToolCallBlockFeature()
            })

            // Choice interaction
            ToolCallBlockView(store: Store(initialState: ToolCallBlockFeature.State(
                id: UUID(),
                toolCallId: "select_branch",
                name: "select_branch",
                arguments: "{}",
                status: .awaitingUser(.choice(prompt: "Which branch?", options: ["main", "develop", "feature/auth"]))
            )) {
                ToolCallBlockFeature()
            })

            ToolCallBlockView(store: Store(initialState: ToolCallBlockFeature.State(
                id: UUID(),
                toolCallId: "read_file",
                name: "read_file",
                arguments: "{\"path\": \"/Users/test/file.txt\"}",
                status: .executing,
                result: "{\"content\": \"file contents here...\"}"
            )) {
                ToolCallBlockFeature()
            })

            ToolCallBlockView(store: Store(initialState: ToolCallBlockFeature.State(
                id: UUID(),
                toolCallId: "read_file",
                name: "read_file",
                arguments: "{\"path\": \"/Users/test/file.txt\"}",
                status: .completed,
                result: "{\"content\": \"file contents here...\"}",
                isExpanded: true
            )) {
                ToolCallBlockFeature()
            })

            ToolCallBlockView(store: Store(initialState: ToolCallBlockFeature.State(
                id: UUID(),
                toolCallId: "read_file",
                name: "read_file",
                arguments: "{\"path\": \"/Users/test/file.txt\"}",
                status: .denied
            )) {
                ToolCallBlockFeature()
            })

            ToolCallBlockView(store: Store(initialState: ToolCallBlockFeature.State(
                id: UUID(),
                toolCallId: "read_file",
                name: "read_file",
                arguments: "{\"path\": \"/Users/test/file.txt\"}",
                status: .failed("cannot access file")
            )) {
                ToolCallBlockFeature()
            })
        }
    }
    .frame(width: 600, height: 800)
    .padding()
}
