//
//  ProjectClient.swift
//  SidePiece
//

import Dependencies
import DependenciesMacros
import Foundation
import UniformTypeIdentifiers

public struct ConversationSearchItem: Sendable, Equatable {
    public let id: UUID
    public let title: String

    public init(id: UUID, title: String) {
        self.id = id
        self.title = title
    }
}

@DependencyClient
public struct ProjectClient: Sendable {
    var index: @Sendable(URL) -> AsyncStream<Void> = { _ in .finished }
    var search: @Sendable(String, [ConversationSearchItem]) async -> [UUID] = { _, _ in [] }
}

extension ProjectClient {
    public enum ProjectClientError: LocalizedError, Sendable, Equatable {
        case failedToEnumerateDirectory
    }
}

extension ProjectClient: DependencyKey {
    public static let liveValue = {
        @Dependency(\.projectIndexerClient) var projectIndexerClient
        @Dependency(\.continuousClock) var clock
        let container = LockIsolated<[URL: AsyncStream<Void>.Continuation]>([:])
        let indexer = projectIndexerClient.indexer()
        return ProjectClient(
            index: { url in
                let (stream, continuation) = AsyncStream.makeStream(of: Void.self)
                container.withValue {
                    $0[url] = continuation
                }
                let task = Task {
                    let didStartAccessing = url.startAccessingSecurityScopedResource()
                    defer { if didStartAccessing { url.stopAccessingSecurityScopedResource() } }
                    
                    let fileManager = FileManager.default
                    let resourceKeys: [URLResourceKey] = [
                      .isDirectoryKey,
                      .isRegularFileKey,
                      .isPackageKey,
                      .contentModificationDateKey,
                      .contentTypeKey,
                      .nameKey
                    ]

                    guard let enumerator = fileManager.enumerator(
                        at: url,
                        includingPropertiesForKeys: resourceKeys,
                        options: [.skipsHiddenFiles]
                    ) else { return /* TODO: Should be an AsyncThrowingStream */ }
                    
                    // TODO: Read files and add them to the indexer
                    
                    let rootPath = url.standardizedFileURL.path
                    let rootPrefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
                    var count = 0
                    while let fileURL = enumerator.nextObject() as? URL {
                        guard !Task.isCancelled else { return }
                        
                        let standardized = fileURL.standardizedFileURL
                        let fullPath = standardized.path
                        
                        let relativePath = if fullPath.hasPrefix(rootPrefix) {
                           String(fullPath.dropFirst(rootPrefix.count))
                        } else {
                            fullPath  // fallback
                        }
                        
                        guard let values = try? standardized.resourceValues(forKeys: Set(resourceKeys))
                        else { return /* TODO: Should be an AsyncThrowingStream */ }
                        let modifiedAt = values.contentModificationDate ?? .distantPast
                        let contentType: UTType = values.contentType ?? .plainText

                        await indexer.add(.init(
                            id: UUID(),
                            relative: relativePath,
                            modified: modifiedAt,
                            contentType: contentType
                        ), to: url)
                        count += 1
                    }
                    
                    // TODO: Add file watcher
                }
                continuation.onTermination = { _ in
                    _ = container.withValue {
                        $0.removeValue(forKey: url)
                    }
                    task.cancel()
                }
                return stream
            },
            search: { term, items in
                guard !term.isEmpty else { return items.map(\.id) }

                let lowercasedTerm = term.lowercased()
                let termChars = Array(lowercasedTerm)

                var scored: [(id: UUID, score: Int)] = []
                for item in items {
                    let title = item.title.lowercased()
                    let score = fuzzyScore(termChars, in: title)
                    if score > 0 {
                        scored.append((item.id, score))
                    }
                }

                scored.sort { $0.score > $1.score }
                return scored.map(\.id)
            }
        )
    }()
}

/// Fast fuzzy scoring: subsequence matching with bonuses for consecutive/boundary matches
private func fuzzyScore(_ termChars: [Character], in target: String) -> Int {
    let targetChars = Array(target)
    guard !targetChars.isEmpty else { return 0 }

    // Quick check: at least one character must exist
    var hasAnyMatch = false
    for char in termChars {
        if targetChars.contains(char) {
            hasAnyMatch = true
            break
        }
    }
    guard hasAnyMatch else { return 0 }

    var score = 1 // Base score for any match
    var termIndex = 0
    var consecutive = 0
    var lastMatchIndex = -2

    for (i, char) in targetChars.enumerated() {
        guard termIndex < termChars.count else { break }

        if char == termChars[termIndex] {
            score += 1

            // Consecutive match bonus
            if i == lastMatchIndex + 1 {
                consecutive += 1
                score += consecutive * 3
            } else {
                consecutive = 0
            }

            // Start of string bonus
            if i == 0 { score += 15 }

            // Word boundary bonus (after / _ - . or space)
            if i > 0 {
                let prev = targetChars[i - 1]
                if prev == "/" || prev == "_" || prev == "-" || prev == "." || prev == " " {
                    score += 8
                }
            }

            lastMatchIndex = i
            termIndex += 1
        }
    }

    // Full subsequence match bonus
    if termIndex == termChars.count {
        score += 25

        // Exact substring bonus (all chars consecutive in target)
        let termString = String(termChars)
        if target.contains(termString) {
            score += 50
            // Prefix match gets extra
            if target.hasPrefix(termString) {
                score += 30
            }
        }
    }

    return score
}

extension DependencyValues {
    public var projectClient: ProjectClient {
        get { self[ProjectClient.self] }
        set { self[ProjectClient.self] = newValue }
    }
}
