//
//  Conversation.swift
//  SidePiece
//

import ComposableArchitecture
import SwiftUI

@Reducer
public struct ConversationFeature: Sendable {
    @ObservableState
    public struct State: Equatable, Identifiable {
        public enum ContextMenuLocation: Equatable {
            public enum Source: Equatable {
                case text
                case button
            }

            case mainTextView(CGRect, Source)
            case messages(UUID, CGRect, Source)
        }
        
        public var id: UUID = UUID()
        var project: URL
        var mainTextView: ContextInputFeature.State
        var messages: MessagesFeature.State? = nil
        var contextMenu: ContextOverlayFeature.State
        var contextMenuOffset: ContextMenuLocation? = nil
        var renameText: String? = nil
        var tokenUsage: TokenUsage = .zero
    }
    
    public enum Action: Equatable {
        case onAppear
        case dismissContextMenu
        case mainTextView(ContextInputFeature.Action)
        case messages(MessagesFeature.Action)
        case contextMenu(ContextOverlayFeature.Action)
        case applyModelSelection(source: ModelSelectionFeature.State.Source, model: Model)
        case beginRename
        case renameTextChanged(String)
        case commitRename
        case cancelRename
        case delegate(DelegateAction)

        @CasePathable
        public enum DelegateAction: Equatable {
            case viewImage(URL)
            case selectModel(
                source: ModelSelectionFeature.State.Source,
                selectedModel: Model?
            )
        }
    }
    
    @Dependency(\.date) var date
    @Dependency(\.uuid) var uuid
    
    public var body: some ReducerOf<Self> {
        Scope(state: \.mainTextView, action: \.mainTextView) {
            ContextInputFeature()
        }
        Scope(state: \.contextMenu, action: \.contextMenu) {
            ContextOverlayFeature()
        }
        
        Reduce { state, action in
            switch action {
            case .onAppear:
                state.mainTextView.inputField.isFocused = true
                return .none

            case .beginRename:
                guard state.displayState == .active else { return .none }
                state.renameText = state.displayTitle
                return .none

            case let .renameTextChanged(text):
                state.renameText = text
                return .none

            case .commitRename:
                guard let text = state.renameText else { return .none }
                let trimmed = text.trimmingCharacters(in: .whitespaces)
                state.renameText = nil
                guard !trimmed.isEmpty, trimmed != state.displayTitle else { return .none }
                return .send(.messages(.title(.rename(trimmed))))

            case .cancelRename:
                state.renameText = nil
                return .none

            case .dismissContextMenu:
                state.contextMenuOffset = nil
                return .send(.contextMenu(.reset))

            case let .mainTextView(.inputField(.delegate(.event(event)))):
                switch event {
                case let .action(event):
                    switch event {
                    case let .command(query, _), let .context(query, _):
                        guard state.contextMenuOffset == nil else {
                            return .send(.contextMenu(.filter(query)))
                        }
                        state.contextMenu.focusTextField = false
                        state.contextMenu.showFilter = false
                        state.contextMenuOffset = .mainTextView(state.mainTextView.frame, .text)
                        return .send(.contextMenu(.filter(query)))
                    case .none:
                        state.contextMenuOffset = nil
                        return .send(.contextMenu(.reset))
                    }
                case let .keyboard(event):
                    switch event {
                    case .cancel:
                        state.contextMenuOffset = nil
                        return .none
                    case .insertNewLine, .insertTab:
                        switch state.mainTextView.inputField.action {
                        case .none:
                            guard !state.isStreaming else {
                                // TODO: Should be adding the message into a queue
                                return .none
                            }
                            return addConversation(&state)

                        case .context, .command:
                            guard let selection = state.contextMenu.selected else { return .none }
                            switch selection {
                            case let .container(data):
                                return .send(.contextMenu(.push(data.items)))
                            case let .item(data):
                                state.mainTextView.inputField.attach(
                                    VSInlineAttachment.VSAttachmentModel(data)
                                )
                                return .none
                            }
                        }
                    case .moveDown:
                        state.contextMenu.down()
                        return .none
                    case .moveUp:
                        state.contextMenu.up()
                        return .none
                    }
                }

            case .mainTextView(.delegate(.submit)):
                return addConversation(&state)

            case .mainTextView(.delegate(.stopStreaming)):
                guard let streamingID = state.messages?.streamingMessageID else { return .none }
                return .send(.messages(.stopStreaming(streamingID)))

            case .mainTextView(.delegate(.contextOverlay)):
                guard state.contextMenuOffset == nil else { return .none }
                state.contextMenu.focusTextField = true
                state.contextMenu.showFilter = true
                state.contextMenuOffset = .mainTextView(state.mainTextView.frame, .button)
                return .none

            case let .mainTextView(.delegate(.frameDidChange(frame))):
                guard case let .mainTextView(_, source) = state.contextMenuOffset else { return .none }
                state.contextMenuOffset = .mainTextView(frame, source)
                return .none

            case let .messages(.messageItems(.element(id, .prompt(.inputField(.delegate(.event(event))))))):
                switch event {
                case let .action(event):
                    switch event {
                    case let .command(query, _), let .context(query, _):
                        guard state.contextMenuOffset == nil else {
                            return .send(.contextMenu(.filter(query)))
                        }
                        guard let messages = state.messages else { return .none }
                        guard let inputField = messages.messageItems[id: id]?.prompt else { return .none }
                        state.contextMenu.focusTextField = false
                        state.contextMenu.showFilter = false
                        state.contextMenuOffset = .messages(id, inputField.frame, .text)
                        return .send(.contextMenu(.filter(query)))
                    case .none:
                        state.contextMenuOffset = nil
                        return .send(.contextMenu(.reset))
                    }
                case let .keyboard(event):
                    switch event {
                    case .cancel:
                        state.contextMenuOffset = nil
                        return .none
                    case .insertNewLine, .insertTab:
                        guard let messages = state.messages else { return .none }
                        guard let inputField = messages.messageItems[id: id]?.prompt.inputField else { return .none }
                        
                        switch inputField.action {
                        case .none:
                            return editConversation(id: id, &state)
                            
                        case .command, .context:
                            guard let selection = state.contextMenu.selected else { return .none }
                            switch selection {
                            case let .container(data):
                                return .send(.contextMenu(.push(data.items)))
                            case let .item(data):
                                state.messages?.messageItems[id: id]?.prompt.inputField.attach(VSInlineAttachment.VSAttachmentModel(data))
                                return .none
                            }
                        }
                    case .moveDown:
                        state.contextMenu.down()
                        return .none
                    case .moveUp:
                        state.contextMenu.up()
                        return .none
                    }
                }
            
            case let .messages(.messageItems(.element(id, .prompt(.delegate(.submit))))):
                return editConversation(id: id, &state)

            case .messages(.messageItems(.element(_, .prompt(.delegate(.stopStreaming))))):
                guard let streamingID = state.messages?.streamingMessageID else { return .none }
                return .send(.messages(.stopStreaming(streamingID)))

            case let .messages(.messageItems(.element(id, .prompt(.delegate(.contextOverlay))))):
                guard state.contextMenuOffset == nil else { return .none }
                guard let messages = state.messages else { return .none }
                guard let prompt = messages.messageItems[id: id]?.prompt else { return .none }
                state.contextMenu.focusTextField = true
                state.contextMenu.showFilter = true
                state.contextMenuOffset = .messages(id, prompt.frame, .button)
                return .none

            case let .messages(.messageItems(.element(id, .prompt(.delegate(.frameDidChange(frame)))))):
                guard case let .messages(messageId, _, source) = state.contextMenuOffset else { return .none }
                guard messageId == id else { return .none }
                state.contextMenuOffset = .messages(id, frame, source)
                return .none
                
            case let .messages(.messageItems(.element(_, action: .response(.delegate(.streamEnded(usage)))))):
                guard let usage else { return .none }
                state.tokenUsage = TokenUsage(
                    promptTokens: state.tokenUsage.promptTokens + usage.promptTokens,
                    completionTokens: state.tokenUsage.completionTokens + usage.completionTokens
                )
                
                return .none

            case let .contextMenu(.select(selection)):
                guard let contextMenuOffset = state.contextMenuOffset else { return .none }
                switch contextMenuOffset {
                case .mainTextView:
                    state.mainTextView.inputField.attach(VSInlineAttachment.VSAttachmentModel(selection))
                case let .messages(id, _, _):
                    state.messages?.messageItems[id: id]?.prompt.inputField.attach(VSInlineAttachment.VSAttachmentModel(selection))
                }
                
                state.contextMenuOffset = nil
                return .none

            case let .mainTextView(.delegate(.viewImage(url))):
                return .send(.delegate(.viewImage(url)))

            case let .messages(.messageItems(.element(_, .prompt(.delegate(.viewImage(url)))))):
                return .send(.delegate(.viewImage(url)))

            case let .mainTextView(.agentToolbar(.delegate(.selectNewModel(current)))):
                return .send(.delegate(.selectModel(
                    source: ModelSelectionFeature.State.Source(
                        inputId: state.mainTextView.id,
                        conversationId: state.id
                    ),
                    selectedModel: current
                )))

            case let .messages(.messageItems(.element(id: id, action: .prompt(.agentToolbar(.delegate(.selectNewModel(current))))))):
                return .send(.delegate(.selectModel(
                    source: ModelSelectionFeature.State.Source(
                        inputId: id,
                        conversationId: state.id
                    ),
                    selectedModel: current
                )))

            case let .applyModelSelection(source, model):
                if state.mainTextView.id == source.inputId {
                    state.mainTextView.agentToolbar.selectedModel = model
                }
                if var agentToolbar = state.messages?.messageItems[id: source.inputId]?.prompt.agentToolbar {
                    agentToolbar.selectedModel = model
                    state.messages?.messageItems[id: source.inputId]?.prompt.agentToolbar = agentToolbar
                }
                return .none

            case .contextMenu:
                return .none
            case .delegate:
                return .none
            case .mainTextView:
                return .none
            case .messages:
                return .none
            }
        }
        .ifLet(\.messages, action: \.messages) {
            MessagesFeature()
        }
    }
    
    func addConversation(_ state: inout ConversationFeature.State) -> Effect<Action> {
        guard case .none = state.mainTextView.inputField.action else { return .none }
        guard let attributedString = state.mainTextView.inputField.textContentStorage.textStorage else {
            return .none
        }
        guard attributedString.length > 0 else { return .none }
        let copiedString = NSAttributedString(
            attributedString: attributedString
        )
        attributedString.setAttributedString(NSAttributedString())
        if state.messages == nil {
            state.messages = MessagesFeature.State(
                date: date(),
                model: state.mainTextView.agentToolbar.selectedModel,
                projectURL: state.project
            )
        }
        let prompt = ContextInputFeature.State(
            inputField: TextInputFeature.State(
                copy: state.mainTextView.inputField,
                initialString: copiedString
            ),
            images: state.mainTextView.images,
            agentToolbar: state.mainTextView.agentToolbar,
            toolbarMode: .expandOnFocus
        )
        
        state.mainTextView.images = ContextImageSelectionFeature.State()
        
        return .send(.messages(.startStreaming(prompt)))
    }
    
    func editConversation(id: UUID, _ state: inout ConversationFeature.State) -> Effect<Action> {
        guard var messages = state.messages else { return .none }
        guard let index = messages.messageItems.index(id: id) else { return .none }
        // TODO: Need to explicitly stop any messages that appear after this one
        let nextIndex = messages.messageItems.index(after: index)
        messages.messageItems.removeSubrange(nextIndex...)
        state.messages = messages
        state.mainTextView.inputField.isFocused = true
        state.tokenUsage = .zero // TODO: This is not right. We dont track how many tokens each individual message contributed, so we just reset to zero. We can improve this by tracking the usage, but then we have to manage another map

        return .send(.messages(.restartStreaming(id)))
    }
}

private extension TextInputFeature.State {
    init(
        copy: TextInputFeature.State,
        initialString: NSAttributedString? = nil
    ) {
        self.init(
            minHeight: copy.minHeight,
            maxHeight: copy.maxHeight,
            height: copy.height,
            font: copy.font,
            fontForegroundColor: copy.fontForegroundColor,
            lineSpacing: copy.lineSpacing,
            placeholder: copy.placeholder,
            initialString: initialString
        )
    }
}

private extension VSInlineAttachment.VSAttachmentModel {
    init(_ item: ContextItem.ItemData) {
        self.id = item.id
        switch item.type {
        case .tool:
            self.type = .tool(item.title, item.icon)
        case let .file(url, type):
            self.type = .file(url, type)
        }
    }
}

// MARK: - Conversation State

extension ConversationFeature.State {
    /// Represents the display state of a conversation in the sidebar
    enum DisplayState: Equatable {
        case empty           // No messages, no draft text
        case draft           // No messages, has draft text
        case streaming       // Has messages, actively streaming
        case active          // Has messages, not streaming
    }

    /// The current display state - determines icon and title shown in sidebar
    var displayState: DisplayState {
        if let messages = messages {
            return messages.streamingMessageID != nil ? .streaming : .active
        } else {
            return hasDraftContent ? .draft : .empty
        }
    }

    /// Whether the main text view has content (used internally for draft detection)
    private var hasDraftContent: Bool {
        guard let textStorage = mainTextView.inputField.textContentStorage.textStorage else {
            return false
        }
        return textStorage.length > 0
    }

    var isEmpty: Bool {
        displayState == .empty
    }

    var isDraft: Bool {
        displayState == .draft
    }

    var isActive: Bool {
        if case .active = displayState { return true }
        if case .streaming = displayState { return true }
        return false
    }

    var isStreaming: Bool {
        displayState == .streaming
    }
    
    var icon: some View {
        if isStreaming {
            return AnyView(ProgressView()
                .controlSize(.small)
                .scaleEffect(0.7))
        } else if isDraft {
            return AnyView(Image(systemName: "pencil"))
        } else if isEmpty {
            return AnyView(Image(systemName: "plus.message"))
        } else {
            let icon = messages?.messageItems.first?.prompt.agentToolbar.selectedAgent.icon ?? Image(systemName: "message")
            return AnyView(icon)
        }
    }

    var displayTitle: String {
        switch displayState {
        case .empty:
            return "New agent"
        case .draft:
            return "Draft"
        case .streaming, .active:
            guard let messages = messages else { return "Untitled" }
            return messages.title.displayTitle
        }
    }
    
    var displayTime: String {
        guard let messages else { return "" }
        return messages.relativeTimestamp
    }

    var draftPreview: String {
        guard let textStorage = mainTextView.inputField.textContentStorage.textStorage else {
            return ""
        }
        let text = textStorage.string
        let preview = String(text.prefix(30))
        return preview.isEmpty ? "Untitled" : preview
    }

    // MARK: - Row Actions

    enum RowAction: Equatable, Identifiable {
        case rename
        case delete

        var id: String {
            switch self {
            case .rename: return "rename"
            case .delete: return "delete"
            }
        }

        var title: String {
            switch self {
            case .rename: return "Rename"
            case .delete: return "Delete"
            }
        }

        var systemImage: String {
            switch self {
            case .rename: return "pencil"
            case .delete: return "trash"
            }
        }

        var role: ButtonRole? {
            switch self {
            case .rename: return nil
            case .delete: return .destructive
            }
        }
    }

    var rowActions: [RowAction] {
        switch displayState {
        case .active:
            return [.rename, .delete]
        case .draft, .streaming:
            return [.delete]
        case .empty:
            return []
        }
    }
}

struct ConversationView: View {
    @Bindable var store: StoreOf<ConversationFeature>
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            if let messagesStore = store.scope(
                state: \.messages,
                action: \.messages
            ) {
                MessagesView(
                    store: messagesStore,
                    isStreaming: store.isStreaming,
                    tokenUsage: store.tokenUsage
                )
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity
                )
            }
            ContextInputView(
                store: store.scope(
                    state: \.mainTextView,
                    action: \.mainTextView
                ),
                isStreaming: store.isStreaming,
                tokenUsage: store.tokenUsage
            )
            Spacer()
            Text("AI can make mistakes. Please double-check cited sources.")
                .font(theme.typography.caption())
                .foregroundStyle(.tertiary)
        }
        .coordinateSpace(name: "conversationView")
        .frame(maxWidth: 960)
        .overlay {
            if store.contextMenuOffset != nil {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        store.send(.dismissContextMenu)
                    }
            }
        }
        .overlay(alignment: .topLeading) {
            if let offset = store.contextMenuOffset {
                let overlaySize = CGSize(width: 290, height: 224)
                ContextOverlayView(store: store.scope(state: \.contextMenu, action: \.contextMenu))
                    .frame(
                        width: overlaySize.width,
                        height: overlaySize.height
                    )
                    .offset(computeOffset(offset, size: overlaySize))
            }
        }
        .padding()
        .onKeyPress(.escape) {
            guard store.contextMenuOffset != nil else { return .ignored }
            store.send(.dismissContextMenu)
            return .handled
        }
        .onAppear {
            store.send(.onAppear)
        }
    }

    func computeOffset(_ location: ConversationFeature.State.ContextMenuLocation, size: CGSize) -> CGSize {
        let frame = location.frame
        let xOffset: CGFloat = switch location.source {
        case .text:
            frame.origin.x + 4
        case .button:
            frame.maxX - size.width - 4
        }

        if frame.origin.y < size.height {
            return CGSize(
                width: xOffset,
                height: frame.origin.y + frame.size.height - 12 // the 12 should really be the height of the toolbar
            )
        } else {
            return CGSize(
                width: xOffset,
                height: frame.origin.y - size.height + 4 // the 4 just makes it feel like part of the input field
            )
        }
    }
}

private extension ConversationFeature.State.ContextMenuLocation {
    var frame: CGRect {
        switch self {
        case let .mainTextView(rect, _):
            rect
        case let .messages(_, rect, _):
            rect
        }
    }

    var source: Source {
        switch self {
        case let .mainTextView(_, source):
            source
        case let .messages(_, _, source):
            source
        }
    }
}
