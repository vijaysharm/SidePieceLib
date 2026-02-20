//
//  RecentProject.swift
//  SidePiece
//

import Foundation

public struct RecentProject: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    let bookmarkData: Data
    let displayName: String
    let pathString: String
    let lastAccessed: Date
    
    init(
        id: UUID,
        url: URL,
        bookmarkData: Data,
        lastAccessed: Date
    ) {
        self.id = id
        self.bookmarkData = bookmarkData
        self.displayName = url.lastPathComponent
        self.pathString = url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        self.lastAccessed = lastAccessed
    }
}
