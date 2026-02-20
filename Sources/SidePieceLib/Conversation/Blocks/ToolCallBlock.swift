//
//  ToolCallBlock.swift
//  SidePiece
//

import ComposableArchitecture
import SwiftUI

enum ToolCallStatus: Equatable, Sendable {
    case streaming              // Arguments still arriving
    case waitingForPriorTool    // Waiting for earlier tool to get permission
    case pendingPermission      // Waiting for user approval (this is the active one)
    case denied                 // User denied permission
    
    case executing              // Tool is running
    case completed              // Finished successfully
    case failed(String)         // Execution failed with error message
    
    var isActive: Bool {
        switch self {
        case .streaming, .waitingForPriorTool, .pendingPermission, .executing:
            true
        case .completed, .denied, .failed:
            false
        }
    }
}

enum ToolPermissionDecision: Equatable, Sendable {
    case allowOnce
    case allowAlways
    case deny
}

enum ToolExecutionError: LocalizedError, Equatable {
    case unknown(String)
}

enum AllowAction: String, CaseIterable, Equatable, Sendable {
    case allowOnce = "Allow Once"
    case allowAlways = "Allow Always"
}

@Reducer
struct ToolCallBlockFeature: Sendable {
    @ObservableState
    struct State: Identifiable, Equatable, Sendable {
        let id: UUID
        let toolCallId: String
        var name: String
        var arguments: String
        var status: ToolCallStatus
        var result: String?
        var isExpanded: Bool = false
        var selectedAllowAction: AllowAction = .allowAlways
    }

    enum Action: Equatable, Sendable {
        @CasePathable
        enum DelegateAction: Equatable, Sendable {
            case response(ToolPermissionDecision)
        }

        @CasePathable
        enum InternalAction: Equatable, Sendable {
            case toggleExpanded
            case setAllowAction(AllowAction)
        }

        case `internal`(InternalAction)
        case delegate(DelegateAction)
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .internal(.toggleExpanded):
                state.isExpanded.toggle()
                return .none
            case let .internal(.setAllowAction(action)):
                state.selectedAllowAction = action
                return .none
            case .internal, .delegate:
                return .none
            }
        }
    }
}

struct ToolCallBlockView: View {
    @Bindable var store: StoreOf<ToolCallBlockFeature>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header row with tool name, chevron, and permission controls
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

                // Right side: permission controls (only for pendingPermission)
                if case .pendingPermission = store.status {
                    PermissionControls(
                        selectedAction: store.selectedAllowAction,
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
                }
            }
            .animation(nil, value: store.isExpanded)

            // Expanded content
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

fileprivate struct PermissionControls: View {
    let selectedAction: AllowAction
    let onDeny: () -> Void
    let onAllow: (ToolPermissionDecision) -> Void
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
            AllowSplitButton(
                selectedAction: selectedAction,
                onAllow: onAllow,
                onSelectAction: onSelectAction
            )
        }
    }
}

fileprivate struct AllowSplitButton: View {
    let selectedAction: AllowAction
    let onAllow: (ToolPermissionDecision) -> Void
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

            // Pending permission - collapsed (shows buttons in header)
            ToolCallBlockView(store: Store(initialState: ToolCallBlockFeature.State(
                id: UUID(),
                toolCallId: "read_file",
                name: "read_file",
                arguments: "{\"path\": \"/Users/test/file.txt\"}",
                status: .pendingPermission
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
    .frame(width: 600, height: 600)
    .padding()
}
