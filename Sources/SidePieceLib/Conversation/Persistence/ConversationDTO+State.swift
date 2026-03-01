//
//  ConversationDTO+State.swift
//  SidePiece
//

import AppKit
import ComposableArchitecture
import Foundation
import SwiftUI
import UniformTypeIdentifiers

// MARK: - State -> DTO

extension ConversationFeature.State {
    func toDTO() -> ConversationDTO {
        var dto = ConversationDTO(
            id: id,
            projectPath: project.path,
            tokenUsage: tokenUsage
        )

        if let messages = messages {
            dto.messages = messages.toDTO()
        }

        // Save draft if there's text but no messages
        if messages == nil {
            let draftText = mainTextView.inputField.textContentStorage.textStorage?.string ?? ""
            let attachments = extractAttachments(from: mainTextView.inputField)
            let imageFiles = mainTextView.images.files.map { $0.toDTO() }

            if !draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !attachments.isEmpty
                || !imageFiles.isEmpty
            {
                dto.draft = DraftDTO(
                    text: draftText,
                    attachments: attachments,
                    imageFiles: imageFiles,
                    agentId: mainTextView.agentToolbar.selectedAgent.name,
                    modelId: mainTextView.agentToolbar.selectedModel.id.description
                )
            }
        }

        return dto
    }

    func toIndexEntry() -> ConversationIndexEntry {
        let messageCount = messages?.messageItems.count ?? 0
        let title: String
        let modelId: String
        let modelDisplayName: String
        let agentId: String
        let date: Date
        let hasDraft = messages == nil && isDraft

        if let messages = messages {
            title = messages.title.displayTitle
            modelId = messages.model.id.description
            modelDisplayName = messages.model.displayName
            agentId = messages.messageItems.first?.prompt.agentToolbar.selectedAgent.name ?? mainTextView.agentToolbar.selectedAgent.name
            date = messages.date
        } else {
            title = draftPreview
            modelId = mainTextView.agentToolbar.selectedModel.id.description
            modelDisplayName = mainTextView.agentToolbar.selectedModel.displayName
            agentId = mainTextView.agentToolbar.selectedAgent.name
            @Dependency(\.date) var dateDep
            date = dateDep()
        }

        return ConversationIndexEntry(
            id: id,
            title: title,
            modelDisplayName: modelDisplayName,
            date: date,
            modelId: modelId,
            agentId: agentId,
            messageCount: messageCount,
            lastModified: Date(),
            isDraft: hasDraft
        )
    }
}

extension MessagesFeature.State {
    func toDTO() -> MessagesDTO {
        MessagesDTO(
            title: title.title.toDTO(),
            date: date,
            modelId: model.id.description,
            messageItems: messageItems.map { $0.toDTO() },
            allowedTools: Array(allowedTools)
        )
    }
}

extension MessageTitleFeature.TitleType {
    func toDTO() -> TitleDTO {
        switch self {
        case let .placeholder(s): .placeholder(s)
        case let .title(s): .title(s)
        }
    }
}

extension MessageItemFeature.State {
    func toDTO() -> MessageItemDTO {
        MessageItemDTO(
            id: id,
            prompt: prompt.toPromptDTO(),
            history: history.map { $0.toDTO() },
            response: response.toDTO()
        )
    }
}

extension ContextInputFeature.State {
    func toPromptDTO() -> PromptDTO {
        PromptDTO(
            id: id,
            text: inputField.textContentStorage.textStorage?.string ?? "",
            attachments: extractAttachments(from: inputField),
            imageFiles: images.files.map { $0.toDTO() },
            agentId: agentToolbar.selectedAgent.name,
            modelId: agentToolbar.selectedModel.id.description
        )
    }
}

extension MessageItemResponseFeature.State {
    func toDTO() -> ResponseDTO {
        ResponseDTO(blocks: blocks.map { $0.toDTO() })
    }
}

extension ResponseBlockFeature.State {
    func toDTO() -> ResponseBlockDTO {
        switch self {
        case let .text(data):
            .text(TextBlockDTO(id: data.id, content: data.content))
        case let .reasoning(data):
            .reasoning(ReasoningBlockDTO(id: data.id, content: data.content, isExpanded: data.isExpanded))
        case let .toolCall(data):
            .toolCall(ToolCallBlockDTO(
                id: data.id,
                toolCallId: data.toolCallId,
                name: data.name,
                arguments: data.arguments,
                status: data.status.toDTO(),
                result: data.result
            ))
        case let .error(data):
            .error(ErrorBlockDTO(id: data.id, code: data.error.code, message: data.error.message, underlying: data.error.underlying))
        }
    }
}

extension ToolCallStatus {
    func toDTO() -> ToolCallStatusDTO {
        switch self {
        case .completed: .completed
        case .denied: .denied
        case let .failed(error): .failed(error.toDTO())
        // Non-terminal states map to completed (app was closed mid-operation)
        case .streaming, .executing, .awaitingUser, .waitingForPriorTool: .completed
        }
    }
}

extension ToolExecutionError {
    func toDTO() -> ToolExecutionErrorDTO {
        let type: String
        switch self {
        case .toolNotFound: type = "toolNotFound"
        case .fileNotFound: type = "fileNotFound"
        case .directoryNotFound: type = "directoryNotFound"
        case .invalidArguments: type = "invalidArguments"
        case .executionFailed: type = "executionFailed"
        case .unknown: type = "unknown"
        }
        return ToolExecutionErrorDTO(type: type, message: errorDescription ?? "Tool execution failed")
    }
}

extension ConversationItem {
    func toDTO() -> ConversationItemDTO {
        switch self {
        case let .message(role, content):
            .message(role: role.rawValue, content: content.map { $0.toDTO() })
        case let .toolCall(id, name, arguments):
            .toolCall(id: id, name: name, arguments: arguments)
        case let .toolResult(id, output):
            .toolResult(id: id, output: output)
        }
    }
}

extension ContentPart {
    func toDTO() -> ContentPartDTO {
        switch self {
        case let .text(string):
            .text(string)
        case let .image(source):
            .image(url: source.url.absoluteString, contentType: source.contentType.identifier)
        case let .file(source):
            .file(url: source.url.absoluteString, contentType: source.contentType.identifier)
        }
    }
}

extension ManagedFile {
    func toDTO() -> ManagedFileDTO {
        ManagedFileDTO(
            id: id,
            originalFilename: originalFilename,
            storedFilename: storedFilename,
            dateAdded: dateAdded,
            fileSize: fileSize,
            contentType: contentType.identifier,
            url: url.absoluteString
        )
    }
}

// MARK: - DTO -> State

extension ConversationDTO {
    func toState(project: URL, models: Models, agents: Agents) -> ConversationFeature.State {
        let model = rehydrateModel(id: draft?.modelId ?? messages?.modelId ?? "", from: models)
        let agent = rehydrateAgent(name: draft?.agentId ?? messages?.messageItems.first?.prompt.agentId ?? "", from: agents)

        var inputField = TextInputFeature.State(
            maxLines: 3,
            font: .monospacedSystemFont(ofSize: 15, weight: .regular),
            fontForegroundColor: .white,
            lineSpacing: 4,
            placeholder: "'@' for context menu"
        )

        // If there's a draft, populate the input field
        if let draftDTO = draft {
            let initialString = buildAttributedString(
                text: draftDTO.text,
                attachments: draftDTO.attachments,
                font: .monospacedSystemFont(ofSize: 15, weight: .regular)
            )
            inputField = TextInputFeature.State(
                maxLines: 3,
                font: .monospacedSystemFont(ofSize: 15, weight: .regular),
                fontForegroundColor: .white,
                lineSpacing: 4,
                placeholder: "'@' for context menu",
                initialString: initialString
            )
        }

        var agentToolbar = ContextAgentToolbarFeature.State(models: models, agents: agents)
        agentToolbar.selectedModel = model
        agentToolbar.selectedAgent = agent

        var images = ContextImageSelectionFeature.State()
        if let draftDTO = draft {
            images.files = draftDTO.imageFiles.compactMap { $0.toManagedFile() }
        }

        var state = ConversationFeature.State(
            id: id,
            project: project,
            mainTextView: ContextInputFeature.State(
                inputField: inputField,
                images: images,
                agentToolbar: agentToolbar
            ),
            contextMenu: ContextOverlayFeature.State(project: project),
            tokenUsage: tokenUsage ?? .zero
        )

        if let messagesDTO = messages {
            state.messages = messagesDTO.toState(models: models, agents: agents, projectURL: project)
        }

        return state
    }
}

extension MessagesDTO {
    func toState(models: Models, agents: Agents, projectURL: URL) -> MessagesFeature.State {
        let model = rehydrateModel(id: modelId, from: models)
        return MessagesFeature.State(
            title: MessageTitleFeature.State(title: title.toTitleType()),
            date: date,
            model: model,
            projectURL: projectURL,
            messageItems: IdentifiedArrayOf(uniqueElements: messageItems.map { $0.toState(models: models, agents: agents, projectURL: projectURL) }),
            allowedTools: Set(allowedTools)
        )
    }
}

extension TitleDTO {
    func toTitleType() -> MessageTitleFeature.TitleType {
        switch self {
        case let .placeholder(s): .placeholder(s)
        case let .title(s): .title(s)
        }
    }
}

extension MessageItemDTO {
    func toState(models: Models, agents: Agents, projectURL: URL) -> MessageItemFeature.State {
        MessageItemFeature.State(
            id: id,
            projectURL: projectURL,
            prompt: prompt.toState(models: models, agents: agents),
            history: history.map { $0.toConversationItem() },
            response: response.toState(projectURL: projectURL)
        )
    }
}

extension PromptDTO {
    func toState(models: Models, agents: Agents) -> ContextInputFeature.State {
        let model = rehydrateModel(id: modelId, from: models)
        let agent = rehydrateAgent(name: self.agentId, from: agents)
        let font = NSFont.monospacedSystemFont(ofSize: 15, weight: .regular)

        let initialString = buildAttributedString(
            text: text,
            attachments: attachments,
            font: font
        )

        let inputField = TextInputFeature.State(
            maxLines: 3,
            font: font,
            fontForegroundColor: .white,
            lineSpacing: 4,
            placeholder: "'@' for context menu",
            initialString: initialString
        )

        var agentToolbar = ContextAgentToolbarFeature.State(models: models, agents: agents)
        agentToolbar.selectedModel = model
        agentToolbar.selectedAgent = agent

        var images = ContextImageSelectionFeature.State()
        images.files = imageFiles.compactMap { $0.toManagedFile() }

        return ContextInputFeature.State(
            id: id,
            inputField: inputField,
            images: images,
            agentToolbar: agentToolbar,
            toolbarMode: .expandOnFocus
        )
    }
}

extension ResponseDTO {
    func toState(projectURL: URL) -> MessageItemResponseFeature.State {
        MessageItemResponseFeature.State(
            projectURL: projectURL,
            blocks: IdentifiedArrayOf(uniqueElements: blocks.map { $0.toState() })
        )
    }
}

extension ResponseBlockDTO {
    func toState() -> ResponseBlockFeature.State {
        switch self {
        case let .text(dto):
            .text(TextBlockFeature.State(id: dto.id, content: dto.content, isStreaming: false))
        case let .reasoning(dto):
            .reasoning(ReasoningBlockFeature.State(id: dto.id, content: dto.content, isStreaming: false, isExpanded: dto.isExpanded))
        case let .toolCall(dto):
            .toolCall(ToolCallBlockFeature.State(
                id: dto.id,
                toolCallId: dto.toolCallId,
                name: dto.name,
                arguments: dto.arguments,
                status: dto.status.toToolCallStatus(),
                result: dto.result
            ))
        case let .error(dto):
            .error(ErrorBlockFeature.State(id: dto.id, error: LLMError(code: dto.code, message: dto.message, underlying: dto.underlying)))
        }
    }
}

extension ToolCallStatusDTO {
    func toToolCallStatus() -> ToolCallStatus {
        switch self {
        case .completed: .completed
        case .denied: .denied
        case let .failed(errorDTO): .failed(errorDTO.toToolExecutionError())
        }
    }
}

extension ToolExecutionErrorDTO {
    func toToolExecutionError() -> ToolExecutionError {
        switch type {
        case "toolNotFound": .toolNotFound(name: message)
        case "fileNotFound": .fileNotFound(path: message)
        case "directoryNotFound": .directoryNotFound(path: message)
        case "invalidArguments": .invalidArguments(message: message)
        case "executionFailed": .executionFailed(message: message)
        default: .unknown(message: message)
        }
    }
}

extension ConversationItemDTO {
    func toConversationItem() -> ConversationItem {
        switch self {
        case let .message(role, content):
            .message(
                role: MessageRole(rawValue: role) ?? .user,
                content: content.map { $0.toContentPart() }
            )
        case let .toolCall(id, name, arguments):
            .toolCall(id: id, name: name, arguments: arguments)
        case let .toolResult(id, output):
            .toolResult(id: id, output: output)
        }
    }
}

extension ContentPartDTO {
    func toContentPart() -> ContentPart {
        switch self {
        case let .text(string):
            return .text(string)
        case let .image(urlString, contentTypeId):
            let url = URL(fileURLWithPath: urlString)
            let contentType = UTType(contentTypeId) ?? .jpeg
            return .image(FileSource(url: url, contentType: contentType))
        case let .file(urlString, contentTypeId):
            let url = URL(fileURLWithPath: urlString)
            let contentType = UTType(contentTypeId) ?? .plainText
            return .file(FileSource(url: url, contentType: contentType))
        }
    }
}

extension ManagedFileDTO {
    func toManagedFile() -> ManagedFile? {
        guard let url = URL(string: url) else { return nil }
        let contentType = UTType(contentType) ?? .data
        return ManagedFile(
            id: id,
            originalFilename: originalFilename,
            storedFilename: storedFilename,
            dateAdded: dateAdded,
            fileSize: fileSize,
            contentType: contentType,
            url: url
        )
    }
}

// MARK: - Helpers

private func rehydrateModel(id: String, from models: Models) -> Model {
    models.models.first { $0.id.description == id } ?? models.default
}

private func rehydrateAgent(name: String, from agents: Agents) -> Agent {
    agents.agents.first { $0.name == name } ?? agents.default
}

private func buildAttributedString(
    text: String,
    attachments: [AttachmentDTO],
    font: NSFont
) -> NSAttributedString {
    let defaultAttributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.white,
    ]
    let mutableString = NSMutableAttributedString(
        string: text,
        attributes: defaultAttributes
    )

    guard !attachments.isEmpty else { return mutableString }

    let nsString = mutableString.string as NSString
    var attachmentIndex = 0

    for i in 0..<nsString.length {
        guard attachmentIndex < attachments.count else { break }
        if nsString.character(at: i) == 0xFFFC {
            let dto = attachments[attachmentIndex]
            let model = dto.toAttachmentModel()
            let cell = VSInlineAttachment(data: model, font: font)
            mutableString.addAttribute(
                .attachment, value: cell,
                range: NSRange(location: i, length: 1)
            )
            attachmentIndex += 1
        }
    }

    return mutableString
}

extension AttachmentDTO {
    func toAttachmentModel() -> VSInlineAttachment.VSAttachmentModel {
        switch type {
        case let .file(urlString, contentTypeId):
            let url = URL(fileURLWithPath: urlString)
            let contentType = UTType(contentTypeId) ?? .data
            return VSInlineAttachment.VSAttachmentModel(
                id: id,
                type: .file(url, contentType)
            )
        case let .tool(name):
            return VSInlineAttachment.VSAttachmentModel(
                id: id,
                type: .tool(name, Image(systemName: "hammer"))
            )
        }
    }
}

private func extractAttachments(from inputField: TextInputFeature.State) -> [AttachmentDTO] {
    guard let attributedString = inputField.textContentStorage.textStorage else { return [] }
    var attachments: [AttachmentDTO] = []
    let fullRange = NSRange(location: 0, length: attributedString.length)
    attributedString.enumerateAttribute(.attachment, in: fullRange, options: []) { value, _, _ in
        guard let attachment = value as? VSInlineAttachment else { return }
        let dto: AttachmentDTO
        switch attachment.data.type {
        case let .file(url, contentType):
            dto = AttachmentDTO(
                id: attachment.data.id,
                type: .file(url: url.absoluteString, contentType: contentType.identifier)
            )
        case let .tool(name, _):
            dto = AttachmentDTO(
                id: attachment.data.id,
                type: .tool(name: name)
            )
        }
        attachments.append(dto)
    }
    return attachments
}
