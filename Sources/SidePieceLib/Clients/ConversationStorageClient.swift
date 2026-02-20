//
//  ConversationStorageClient.swift
//  SidePiece
//

import CryptoKit
import Dependencies
import DependenciesMacros
import Foundation

@DependencyClient
struct ConversationStorageClient: Sendable {
    /// Save a conversation (write file + update index)
    var save: @Sendable (_ conversation: ConversationDTO, _ indexEntry: ConversationIndexEntry, _ projectURL: URL) async throws -> Void

    /// Load a single conversation by ID
    var load: @Sendable (_ id: UUID, _ projectURL: URL) async throws -> ConversationDTO?

    /// Delete a conversation
    var delete: @Sendable (_ id: UUID, _ projectURL: URL) async throws -> Void

    /// Delete all conversations for a project
    var deleteAll: @Sendable (_ projectURL: URL) async throws -> Void

    /// Load the index for a project
    var loadIndex: @Sendable (_ projectURL: URL) async throws -> ConversationIndex

    /// Load a page of conversations (sorted by lastModified desc)
    var loadPage: @Sendable (_ projectURL: URL, _ offset: Int, _ limit: Int) async throws -> [ConversationDTO]
}

// MARK: - Helpers

private enum ConversationStorageHelpers {
    static var baseDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let bundleId = Bundle.main.bundleIdentifier ?? "com.sidepiece"
        return appSupport
            .appendingPathComponent(bundleId)
            .appendingPathComponent("Conversations")
    }

    static func projectDirectory(for projectURL: URL) -> URL {
        let hash = SHA256.hash(data: Data(projectURL.path.utf8))
        let prefix = hash.prefix(16).map { String(format: "%02x", $0) }.joined()
        return baseDirectory.appendingPathComponent(prefix)
    }

    static func indexURL(for projectURL: URL) -> URL {
        projectDirectory(for: projectURL).appendingPathComponent("index.json")
    }

    static func conversationURL(for id: UUID, projectURL: URL) -> URL {
        projectDirectory(for: projectURL).appendingPathComponent("\(id.uuidString).json")
    }

    static func ensureDirectory(for projectURL: URL) throws {
        let dir = projectDirectory(for: projectURL)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    static func loadIndex(for projectURL: URL) throws -> ConversationIndex {
        let url = indexURL(for: projectURL)
        guard let data = FileManager.default.contents(atPath: url.path) else {
            return ConversationIndex()
        }
        @Dependency(\.jsonCoder) var coder
        return try coder.decode(ConversationIndex.self, from: data)
    }

    static func saveIndex(_ index: ConversationIndex, for projectURL: URL) throws {
        @Dependency(\.jsonCoder) var coder
        let data = try coder.encode(index)
        let url = indexURL(for: projectURL)
        try data.write(to: url, options: .atomic)
    }
}

// MARK: - Live Implementation

extension ConversationStorageClient: DependencyKey {
    static let liveValue = {
        @Dependency(\.jsonCoder) var coder

        return ConversationStorageClient(
            save: { conversation, indexEntry, projectURL in
                try ConversationStorageHelpers.ensureDirectory(for: projectURL)

                // Write conversation file
                let conversationData = try coder.encode(conversation)
                let conversationURL = ConversationStorageHelpers.conversationURL(for: conversation.id, projectURL: projectURL)
                try conversationData.write(to: conversationURL, options: .atomic)

                // Update index
                var index = try ConversationStorageHelpers.loadIndex(for: projectURL)
                index.entries.removeAll { $0.id == conversation.id }
                index.entries.insert(indexEntry, at: 0)
                try ConversationStorageHelpers.saveIndex(index, for: projectURL)
            },
            load: { id, projectURL in
                let url = ConversationStorageHelpers.conversationURL(for: id, projectURL: projectURL)
                guard let data = FileManager.default.contents(atPath: url.path) else {
                    return nil
                }
                return try coder.decode(ConversationDTO.self, from: data)
            },
            delete: { id, projectURL in
                // Remove file
                let url = ConversationStorageHelpers.conversationURL(for: id, projectURL: projectURL)
                try? FileManager.default.removeItem(at: url)

                // Update index
                var index = try ConversationStorageHelpers.loadIndex(for: projectURL)
                index.entries.removeAll { $0.id == id }
                try ConversationStorageHelpers.saveIndex(index, for: projectURL)
            },
            deleteAll: { projectURL in
                let dir = ConversationStorageHelpers.projectDirectory(for: projectURL)
                try? FileManager.default.removeItem(at: dir)
            },
            loadIndex: { projectURL in
                try ConversationStorageHelpers.loadIndex(for: projectURL)
            },
            loadPage: { projectURL, offset, limit in
                let index = try ConversationStorageHelpers.loadIndex(for: projectURL)
                let sorted = index.entries.sorted { $0.lastModified > $1.lastModified }
                let page = sorted.dropFirst(offset).prefix(limit)

                var conversations: [ConversationDTO] = []
                for entry in page {
                    let url = ConversationStorageHelpers.conversationURL(for: entry.id, projectURL: projectURL)
                    guard let data = FileManager.default.contents(atPath: url.path) else { continue }
                    if let conversation = try? coder.decode(ConversationDTO.self, from: data) {
                        conversations.append(conversation)
                    }
                }
                return conversations
            }
        )
    }()

    static let testValue = ConversationStorageClient()
}

extension DependencyValues {
    var conversationStorageClient: ConversationStorageClient {
        get { self[ConversationStorageClient.self] }
        set { self[ConversationStorageClient.self] = newValue }
    }
}
