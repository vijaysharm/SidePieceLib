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
    /// The user's text is merged into the tool arguments under `argumentKey`.
    case textInput(prompt: String, placeholder: String?, argumentKey: String)

    /// Single choice from a list of options.
    /// The selected option is merged into the tool arguments under `argumentKey`.
    case choice(prompt: String, options: [String], argumentKey: String)

    /// Structured questionnaire — 1 to 4 questions with selectable options.
    /// `questions` defines the form layout; user answers are merged into
    /// the tool arguments under `argumentKey` as a JSON object.
    case questionnaire(questions: [QuestionItem], argumentKey: String)

    /// Whether this interaction type supports "Allow Always" (skipping future interactions).
    /// Text input, choice, and questionnaire always require the user to respond.
    var supportsAlwaysAllow: Bool {
        switch self {
        case .permission, .confirmation: true
        case .textInput, .choice, .questionnaire: false
        }
    }

    /// Merges the user's response value into the original arguments JSON
    /// under the interaction's `argumentKey`. Returns the original arguments
    /// unchanged for `.permission` and `.confirmation`.
    func mergeResponse(_ value: String, into arguments: String) -> String {
        let key: String
        let isObjectValue: Bool

        switch self {
        case let .textInput(_, _, argumentKey):
            key = argumentKey
            isObjectValue = false
        case let .choice(_, _, argumentKey):
            key = argumentKey
            isObjectValue = false
        case let .questionnaire(_, argumentKey):
            key = argumentKey
            isObjectValue = true
        case .permission, .confirmation:
            return arguments
        }

        guard let argsData = arguments.data(using: .utf8),
              var argsObject = try? JSONSerialization.jsonObject(with: argsData) as? [String: Any]
        else { return arguments }

        if isObjectValue,
           let valueData = value.data(using: .utf8),
           let valueObject = try? JSONSerialization.jsonObject(with: valueData) {
            argsObject[key] = valueObject
        } else {
            argsObject[key] = value
        }

        guard let mergedData = try? JSONSerialization.data(withJSONObject: argsObject),
              let mergedString = String(data: mergedData, encoding: .utf8)
        else { return arguments }

        return mergedString
    }
}

// MARK: - Questionnaire Types

/// A single question in a questionnaire interaction, with selectable options.
public struct QuestionItem: Equatable, Sendable, Decodable {
    public let question: String
    public let header: String
    public let options: [QuestionOption]
    public let multiSelect: Bool

    public init(question: String, header: String, options: [QuestionOption], multiSelect: Bool) {
        self.question = question
        self.header = header
        self.options = options
        self.multiSelect = multiSelect
    }
}

/// A selectable option within a questionnaire question.
public struct QuestionOption: Equatable, Sendable, Decodable {
    public let label: String
    public let description: String
    public let markdown: String?

    public init(label: String, description: String, markdown: String? = nil) {
        self.label = label
        self.description = description
        self.markdown = markdown
    }
}

/// Tracks the user's in-progress answers to a questionnaire.
public struct QuestionnaireState: Equatable, Sendable {
    /// Selected option labels per question (keyed by question text).
    public var answers: [String: Set<String>] = [:]
    /// Custom "Other" text per question.
    public var otherText: [String: String] = [:]
    /// Questions where the "Other" option is selected.
    public var otherSelected: Set<String> = []

    /// Encodes the current answers as a JSON string.
    /// Returns the answers dict directly (e.g. `{"q1": "a1"}`).
    /// The framework handles placing this under the correct `argumentKey`.
    public var encodedJSON: String? {
        guard !answers.isEmpty || !otherSelected.isEmpty else { return nil }
        var result: [String: String] = [:]
        let allQuestions = Set(answers.keys).union(otherSelected)
        for question in allQuestions {
            var selections = answers[question].map { Array($0).sorted() } ?? []
            if otherSelected.contains(question),
               let text = otherText[question],
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                selections.append(text)
            }
            result[question] = selections.joined(separator: ", ")
        }
        guard let data = try? JSONSerialization.data(withJSONObject: result),
              let json = String(data: data, encoding: .utf8) else { return nil }
        return json
    }

    /// Whether all questions have been answered (at least one selection or "Other" text per question).
    public func isComplete(for questions: [QuestionItem]) -> Bool {
        for q in questions {
            let hasSelection = !(answers[q.question]?.isEmpty ?? true)
            let hasOther = otherSelected.contains(q.question) &&
                !(otherText[q.question]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            if !hasSelection && !hasOther { return false }
        }
        return true
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

        // Questionnaire state
        var questionnaire: QuestionnaireState = .init()
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
            case toggleQuestionnaireOption(question: String, option: String, multiSelect: Bool)
            case toggleQuestionnaireOther(question: String, multiSelect: Bool)
            case setQuestionnaireOtherText(question: String, text: String)
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
            case let .internal(.toggleQuestionnaireOption(question, option, multiSelect)):
                if multiSelect {
                    var current = state.questionnaire.answers[question] ?? []
                    if current.contains(option) {
                        current.remove(option)
                    } else {
                        current.insert(option)
                    }
                    state.questionnaire.answers[question] = current
                } else {
                    // Single select: replace selection, deselect Other
                    state.questionnaire.answers[question] = [option]
                    state.questionnaire.otherSelected.remove(question)
                }
                return .none
            case let .internal(.toggleQuestionnaireOther(question, multiSelect)):
                if state.questionnaire.otherSelected.contains(question) {
                    state.questionnaire.otherSelected.remove(question)
                } else {
                    state.questionnaire.otherSelected.insert(question)
                    if !multiSelect {
                        // Single select: deselect predefined options
                        state.questionnaire.answers[question] = []
                    }
                }
                return .none
            case let .internal(.setQuestionnaireOtherText(question, text)):
                state.questionnaire.otherText[question] = text
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
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.md) {
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
                                    let trimmed = store.userInputText.trimmingCharacters(in: .whitespacesAndNewlines)
                                    store.send(.delegate(.response(.input(trimmed))))
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

                    case let .questionnaire(questions, _):
                        InputControls(
                            onCancel: {
                                store.send(.delegate(.response(.deny)))
                            },
                            onSubmit: {
                                if let json = store.questionnaire.encodedJSON {
                                    store.send(.delegate(.response(.input(json))))
                                }
                            },
                            isSubmitDisabled: !store.questionnaire.isComplete(for: questions)
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

                case let .textInput(prompt, placeholder, _):
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
                                store.send(.delegate(.response(.input(trimmed))))
                            }
                        }
                    }
                    .padding(.leading, 16)

                case let .choice(prompt, options, _):
                    VStack(alignment: .leading, spacing: 4) {
                        Text(prompt)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)

                        ForEach(Array(options.enumerated()), id: \.offset) { _, option in
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

                case let .questionnaire(questions, _):
                    QuestionnaireView(
                        questions: questions,
                        state: store.questionnaire,
                        onToggleOption: { question, option, multiSelect in
                            store.send(.internal(.toggleQuestionnaireOption(question: question, option: option, multiSelect: multiSelect)))
                        },
                        onToggleOther: { question, multiSelect in
                            store.send(.internal(.toggleQuestionnaireOther(question: question, multiSelect: multiSelect)))
                        },
                        onSetOtherText: { question, text in
                            store.send(.internal(.setQuestionnaireOtherText(question: question, text: text)))
                        }
                    )
                    .padding(.leading, 16)
                }
            }

            // Expanded content (arguments + result)
            if store.isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    if !store.arguments.isEmpty {
                        Text(formatJSON(store.arguments))
                            .font(theme.typography.monoSmall)
                            .foregroundStyle(.tertiary)
                            .textSelection(.enabled)
                    }

                    if let result = store.result {
                        Text(formatJSON(result))
                            .font(theme.typography.monoSmall)
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
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: theme.spacing.xl) {
            // Deny - plain text button
            Button(action: onDeny) {
                Text("Deny")
                    .font(theme.typography.captionSmall)
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
                        .font(theme.typography.captionSmall)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, theme.spacing.lg)
                .padding(.vertical, theme.spacing.sm)
                .background(Color.primary.opacity(0.1))
                .cornerRadius(theme.radius.sm)
            }
        }
    }
}

fileprivate struct InputControls: View {
    let onCancel: () -> Void
    let onSubmit: () -> Void
    let isSubmitDisabled: Bool
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: theme.spacing.xl) {
            Button(action: onCancel) {
                Text("Cancel")
                    .font(theme.typography.captionSmall)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            Button(action: onSubmit) {
                Text("Submit")
                    .font(theme.typography.captionSmall)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
            .disabled(isSubmitDisabled)
            .padding(.horizontal, theme.spacing.lg)
            .padding(.vertical, theme.spacing.sm)
            .background(Color.primary.opacity(isSubmitDisabled ? 0.05 : 0.1))
            .cornerRadius(theme.radius.sm)
        }
    }
}

fileprivate struct AllowSplitButton: View {
    let selectedAction: AllowAction
    let onAllow: (ToolInteractionResponse) -> Void
    let onSelectAction: (AllowAction) -> Void
    @Environment(\.theme) private var theme

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
                    .font(theme.typography.captionSmall)
                    .fontWeight(.medium)
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
            .frame(width: theme.spacing.xl)
        }
        .padding(.horizontal, theme.spacing.lg)
        .padding(.vertical, theme.spacing.sm)
        .background(Color.primary.opacity(0.1))
        .cornerRadius(theme.radius.sm)
    }
}

// MARK: - Questionnaire View

fileprivate struct QuestionnaireView: View {
    let questions: [QuestionItem]
    let state: QuestionnaireState
    let onToggleOption: (_ question: String, _ option: String, _ multiSelect: Bool) -> Void
    let onToggleOther: (_ question: String, _ multiSelect: Bool) -> Void
    let onSetOtherText: (_ question: String, _ text: String) -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xl) {
            ForEach(questions, id: \.question) { question in
                VStack(alignment: .leading, spacing: theme.spacing.sm) {
                    // Header chip + question text
                    HStack(spacing: theme.spacing.sm) {
                        Text(question.header)
                            .font(theme.typography.micro)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, theme.spacing.sm)
                            .padding(.vertical, theme.spacing.xxs)
                            .background(Color.primary.opacity(0.08))
                            .cornerRadius(theme.radius.xs)

                        Text(question.question)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.primary)
                    }

                    // Options
                    let selectedOptions = state.answers[question.question] ?? []
                    let isOtherSelected = state.otherSelected.contains(question.question)

                    ForEach(question.options, id: \.label) { option in
                        let isSelected = selectedOptions.contains(option.label)
                        Button {
                            onToggleOption(question.question, option.label, question.multiSelect)
                        } label: {
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: iconName(selected: isSelected, multiSelect: question.multiSelect))
                                    .font(.system(size: 12))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(option.label)
                                        .font(.system(size: 12))
                                    if !option.description.isEmpty {
                                        Text(option.description)
                                            .font(.system(size: 10))
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                            }
                            .foregroundStyle(isSelected ? .primary : .secondary)
                        }
                        .buttonStyle(.plain)

                        // Show markdown preview when option is selected and has markdown
                        if isSelected, let markdown = option.markdown, !markdown.isEmpty {
                            Text(markdown)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.tertiary)
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.primary.opacity(0.04))
                                .cornerRadius(6)
                                .padding(.leading, 18)
                        }
                    }

                    // "Other" option
                    Button {
                        onToggleOther(question.question, question.multiSelect)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: iconName(selected: isOtherSelected, multiSelect: question.multiSelect))
                                .font(.system(size: 12))
                            Text("Other")
                                .font(.system(size: 12))
                        }
                        .foregroundStyle(isOtherSelected ? .primary : .secondary)
                    }
                    .buttonStyle(.plain)

                    // "Other" text field
                    if isOtherSelected {
                        TextField(
                            "Enter your answer...",
                            text: Binding(
                                get: { state.otherText[question.question] ?? "" },
                                set: { onSetOtherText(question.question, $0) }
                            )
                        )
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                        .padding(.leading, 18)
                    }
                }
            }
        }
    }

    private func iconName(selected: Bool, multiSelect: Bool) -> String {
        if multiSelect {
            return selected ? "checkmark.square.fill" : "square"
        } else {
            return selected ? "checkmark.circle.fill" : "circle"
        }
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
                status: .awaitingUser(.textInput(prompt: "Enter commit message:", placeholder: "feat: ...", argumentKey: "commit_message"))
            )) {
                ToolCallBlockFeature()
            })

            // Choice interaction
            ToolCallBlockView(store: Store(initialState: ToolCallBlockFeature.State(
                id: UUID(),
                toolCallId: "select_branch",
                name: "select_branch",
                arguments: "{}",
                status: .awaitingUser(.choice(prompt: "Which branch?", options: ["main", "develop", "feature/auth"], argumentKey: "branch"))
            )) {
                ToolCallBlockFeature()
            })

            // Questionnaire interaction
            ToolCallBlockView(store: Store(initialState: ToolCallBlockFeature.State(
                id: UUID(),
                toolCallId: "ask_user",
                name: "ask_user_question",
                arguments: """
                {"questions": [{"question": "Which library should we use?", "header": "Library", "options": [{"label": "React", "description": "Popular UI framework"}, {"label": "Vue", "description": "Progressive framework"}], "multi_select": false}, {"question": "Which features do you want?", "header": "Features", "options": [{"label": "Auth", "description": "User authentication"}, {"label": "Caching", "description": "Response caching"}, {"label": "Logging", "description": "Structured logging"}], "multi_select": true}]}
                """,
                status: .awaitingUser(.questionnaire(
                    questions: [
                        QuestionItem(question: "Which library should we use?", header: "Library", options: [
                            QuestionOption(label: "React", description: "Popular UI framework"),
                            QuestionOption(label: "Vue", description: "Progressive framework"),
                        ], multiSelect: false),
                        QuestionItem(question: "Which features do you want?", header: "Features", options: [
                            QuestionOption(label: "Auth", description: "User authentication"),
                            QuestionOption(label: "Caching", description: "Response caching"),
                            QuestionOption(label: "Logging", description: "Structured logging"),
                        ], multiSelect: true),
                    ],
                    argumentKey: "answers"
                ))
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
