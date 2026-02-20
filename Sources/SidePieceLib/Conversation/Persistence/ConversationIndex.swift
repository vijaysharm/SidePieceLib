//
//  ConversationIndex.swift
//  SidePiece
//

import Foundation

struct ConversationIndexEntry: Codable, Sendable, Identifiable {
    let id: UUID
    let title: String
    let modelDisplayName: String
    let date: Date
    let modelId: String
    let agentId: String
    let messageCount: Int
    let lastModified: Date
    let isDraft: Bool
}

struct ConversationIndex: Codable, Sendable {
    var version: Int = 1
    var entries: [ConversationIndexEntry] = []
}
