//
//  ConversationDTO.swift
//  SidePiece
//

import Foundation
import UniformTypeIdentifiers

// MARK: - Top-Level DTO

public struct ConversationDTO: Codable, Sendable, Equatable {
    let id: UUID
    let projectPath: String
    var draft: DraftDTO?
    var messages: MessagesDTO?
    var tokenUsage: TokenUsage?
}

// MARK: - Draft

struct DraftDTO: Codable, Sendable, Equatable {
    var text: String
    var attachments: [AttachmentDTO]
    var imageFiles: [ManagedFileDTO]
    var agentId: String
    var modelId: String
}

// MARK: - Messages

struct MessagesDTO: Codable, Sendable, Equatable {
    var title: TitleDTO
    var date: Date
    var modelId: String
    var messageItems: [MessageItemDTO]
    var allowedTools: [String]
}

// MARK: - Title

enum TitleDTO: Codable, Sendable, Equatable {
    case placeholder(String)
    case title(String)

    private enum CodingKeys: String, CodingKey {
        case type, value
    }

    private enum TitleType: String, Codable {
        case placeholder, title
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .placeholder(value):
            try container.encode(TitleType.placeholder, forKey: .type)
            try container.encode(value, forKey: .value)
        case let .title(value):
            try container.encode(TitleType.title, forKey: .type)
            try container.encode(value, forKey: .value)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(TitleType.self, forKey: .type)
        let value = try container.decode(String.self, forKey: .value)
        switch type {
        case .placeholder: self = .placeholder(value)
        case .title: self = .title(value)
        }
    }
}

// MARK: - Message Item

struct MessageItemDTO: Codable, Sendable, Equatable {
    let id: UUID
    var prompt: PromptDTO
    var history: [ConversationItemDTO]
    var response: ResponseDTO
}

// MARK: - Prompt

struct PromptDTO: Codable, Sendable, Equatable {
    let id: UUID
    var text: String
    var attachments: [AttachmentDTO]
    var imageFiles: [ManagedFileDTO]
    var agentId: String
    var modelId: String
}

// MARK: - Response

struct ResponseDTO: Codable, Sendable, Equatable {
    var blocks: [ResponseBlockDTO]
}

// MARK: - Response Blocks

enum ResponseBlockDTO: Codable, Sendable, Equatable {
    case text(TextBlockDTO)
    case reasoning(ReasoningBlockDTO)
    case toolCall(ToolCallBlockDTO)
    case error(ErrorBlockDTO)

    private enum CodingKeys: String, CodingKey {
        case type, data
    }

    private enum BlockType: String, Codable {
        case text, reasoning, toolCall, error
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .text(block):
            try container.encode(BlockType.text, forKey: .type)
            try container.encode(block, forKey: .data)
        case let .reasoning(block):
            try container.encode(BlockType.reasoning, forKey: .type)
            try container.encode(block, forKey: .data)
        case let .toolCall(block):
            try container.encode(BlockType.toolCall, forKey: .type)
            try container.encode(block, forKey: .data)
        case let .error(block):
            try container.encode(BlockType.error, forKey: .type)
            try container.encode(block, forKey: .data)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(BlockType.self, forKey: .type)
        switch type {
        case .text: self = .text(try container.decode(TextBlockDTO.self, forKey: .data))
        case .reasoning: self = .reasoning(try container.decode(ReasoningBlockDTO.self, forKey: .data))
        case .toolCall: self = .toolCall(try container.decode(ToolCallBlockDTO.self, forKey: .data))
        case .error: self = .error(try container.decode(ErrorBlockDTO.self, forKey: .data))
        }
    }
}

struct TextBlockDTO: Codable, Sendable, Equatable {
    let id: UUID
    var content: String
}

struct ReasoningBlockDTO: Codable, Sendable, Equatable {
    let id: UUID
    var content: String
    var isExpanded: Bool
}

struct ToolCallBlockDTO: Codable, Sendable, Equatable {
    let id: UUID
    let toolCallId: String
    var name: String
    var arguments: String
    var status: ToolCallStatusDTO
    var result: String?
}

struct ToolExecutionErrorDTO: Codable, Sendable, Equatable {
    let type: String
    let message: String
}

enum ToolCallStatusDTO: Codable, Sendable, Equatable {
    case completed
    case denied
    case failed(ToolExecutionErrorDTO)

    private enum CodingKeys: String, CodingKey {
        case type, error, message
    }

    private enum StatusType: String, Codable {
        case completed, denied, failed
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .completed:
            try container.encode(StatusType.completed, forKey: .type)
        case .denied:
            try container.encode(StatusType.denied, forKey: .type)
        case let .failed(errorDTO):
            try container.encode(StatusType.failed, forKey: .type)
            try container.encode(errorDTO, forKey: .error)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(StatusType.self, forKey: .type)
        switch type {
        case .completed: self = .completed
        case .denied: self = .denied
        case .failed:
            // Try new format first (structured error object)
            if let errorDTO = try? container.decode(ToolExecutionErrorDTO.self, forKey: .error) {
                self = .failed(errorDTO)
            } else {
                // Fall back to old format (plain string under "message" key)
                let msg = try container.decode(String.self, forKey: .message)
                self = .failed(ToolExecutionErrorDTO(type: "unknown", message: msg))
            }
        }
    }
}

struct ErrorBlockDTO: Codable, Sendable, Equatable {
    let id: UUID
    var code: String
    var message: String
    var underlying: String?
}

// MARK: - ConversationItem DTO

enum ConversationItemDTO: Codable, Sendable, Equatable {
    case message(role: String, content: [ContentPartDTO])
    case toolCall(id: String, name: String, arguments: String)
    case toolResult(id: String, output: String)

    private enum CodingKeys: String, CodingKey {
        case type, role, content, id, name, arguments, output
    }

    private enum ItemType: String, Codable {
        case message, toolCall, toolResult
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .message(role, content):
            try container.encode(ItemType.message, forKey: .type)
            try container.encode(role, forKey: .role)
            try container.encode(content, forKey: .content)
        case let .toolCall(id, name, arguments):
            try container.encode(ItemType.toolCall, forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(name, forKey: .name)
            try container.encode(arguments, forKey: .arguments)
        case let .toolResult(id, output):
            try container.encode(ItemType.toolResult, forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(output, forKey: .output)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ItemType.self, forKey: .type)
        switch type {
        case .message:
            let role = try container.decode(String.self, forKey: .role)
            let content = try container.decode([ContentPartDTO].self, forKey: .content)
            self = .message(role: role, content: content)
        case .toolCall:
            let id = try container.decode(String.self, forKey: .id)
            let name = try container.decode(String.self, forKey: .name)
            let arguments = try container.decode(String.self, forKey: .arguments)
            self = .toolCall(id: id, name: name, arguments: arguments)
        case .toolResult:
            let id = try container.decode(String.self, forKey: .id)
            let output = try container.decode(String.self, forKey: .output)
            self = .toolResult(id: id, output: output)
        }
    }
}

// MARK: - ContentPart DTO

enum ContentPartDTO: Codable, Sendable, Equatable {
    case text(String)
    case image(url: String, contentType: String)
    case file(url: String, contentType: String)

    private enum CodingKeys: String, CodingKey {
        case type, value, url, contentType
    }

    private enum PartType: String, Codable {
        case text, image, file
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .text(value):
            try container.encode(PartType.text, forKey: .type)
            try container.encode(value, forKey: .value)
        case let .image(url, contentType):
            try container.encode(PartType.image, forKey: .type)
            try container.encode(url, forKey: .url)
            try container.encode(contentType, forKey: .contentType)
        case let .file(url, contentType):
            try container.encode(PartType.file, forKey: .type)
            try container.encode(url, forKey: .url)
            try container.encode(contentType, forKey: .contentType)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(PartType.self, forKey: .type)
        switch type {
        case .text:
            let value = try container.decode(String.self, forKey: .value)
            self = .text(value)
        case .image:
            let url = try container.decode(String.self, forKey: .url)
            let contentType = try container.decode(String.self, forKey: .contentType)
            self = .image(url: url, contentType: contentType)
        case .file:
            let url = try container.decode(String.self, forKey: .url)
            let contentType = try container.decode(String.self, forKey: .contentType)
            self = .file(url: url, contentType: contentType)
        }
    }
}

// MARK: - Attachment DTO

struct AttachmentDTO: Codable, Sendable, Equatable {
    let id: UUID
    var type: AttachmentTypeDTO
}

enum AttachmentTypeDTO: Codable, Sendable, Equatable {
    case file(url: String, contentType: String)
    case tool(name: String)

    private enum CodingKeys: String, CodingKey {
        case type, url, contentType, name
    }

    private enum TypeValue: String, Codable {
        case file, tool
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .file(url, contentType):
            try container.encode(TypeValue.file, forKey: .type)
            try container.encode(url, forKey: .url)
            try container.encode(contentType, forKey: .contentType)
        case let .tool(name):
            try container.encode(TypeValue.tool, forKey: .type)
            try container.encode(name, forKey: .name)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(TypeValue.self, forKey: .type)
        switch type {
        case .file:
            let url = try container.decode(String.self, forKey: .url)
            let contentType = try container.decode(String.self, forKey: .contentType)
            self = .file(url: url, contentType: contentType)
        case .tool:
            let name = try container.decode(String.self, forKey: .name)
            self = .tool(name: name)
        }
    }
}

// MARK: - Managed File DTO

struct ManagedFileDTO: Codable, Sendable, Equatable {
    let id: UUID
    let originalFilename: String
    let storedFilename: String
    let dateAdded: Date
    let fileSize: Int64
    let contentType: String
    let url: String
}
