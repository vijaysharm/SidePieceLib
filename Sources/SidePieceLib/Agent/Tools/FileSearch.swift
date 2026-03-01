//
//  FileSearch.swift
//  SidePiece
//

import Foundation

public struct FileSearchTool: TypedTool {
    public let name = "file_search"
    public let description =
        "Fast fuzzy file search based on matching against file paths. " +
        "Use when you know part of a filename but not its exact location. " +
        "Returns up to 10 results sorted by relevance."

    public struct Input: ToolInput {
        public let query: String
        public let explanation: String

        public static var schema: JSONValue {
            .objectSchema(
                properties: [
                    "query": .stringProperty(description: "Fuzzy filename pattern to search for"),
                    "explanation": .stringProperty(description: "Why this search is being performed"),
                ],
                required: ["query", "explanation"]
            )
        }
    }

    // MARK: - Output

    public struct Output: ToolOutput {
        public let results: [String]

        public var toolResultString: String {
            get throws {
                let result: JSONValue = .object([
                    "results": .array(results.map { .string($0) })
                ])
                return try result.toJSONString()
            }
        }
    }
    
    public func execute(_ input: Input, projectURL: URL) async throws -> Output {
        let fileManager = FileManager.default
        let projectPath = projectURL.path

        guard let enumerator = fileManager.enumerator(
            at: projectURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw ToolExecutionError.directoryNotFound(path: projectPath)
        }

        var scoredPaths: [(path: String, score: Int)] = []
        let queryLower = input.query.lowercased()

        while let fileURL = enumerator.nextObject() as? URL {
            let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard resourceValues?.isRegularFile == true else { continue }

            let fullPath = fileURL.path
            guard fullPath.hasPrefix(projectPath) else { continue }
            let relativePath = String(fullPath.dropFirst(projectPath.count))
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

            let filename = fileURL.lastPathComponent
            let score = Self.fuzzyScore(
                query: queryLower,
                filename: filename.lowercased(),
                path: relativePath.lowercased()
            )
            if score > 0 {
                scoredPaths.append((path: relativePath, score: score))
            }
        }

        let topResults = scoredPaths
            .sorted { $0.score > $1.score }
            .prefix(10)
            .map { $0.path }

        return Output(results: Array(topResults))
    }

    /// Returns a relevance score for how well the query matches the file.
    /// Higher scores indicate better matches. Returns 0 if no match found.
    private static func fuzzyScore(query: String, filename: String, path: String) -> Int {
        if filename == query { return 1000 }
        if filename.hasPrefix(query) { return 900 }
        if filename.contains(query) { return 800 }
        if path.contains(query) { return 600 }
        if let bonus = subsequenceScore(query: query, in: filename) { return 400 + bonus }
        if let bonus = subsequenceScore(query: query, in: path) { return 200 + bonus }
        return 0
    }

    /// Returns a consecutive-match bonus if all query characters appear as a subsequence
    /// in target, or nil if they do not.
    private static func subsequenceScore(query: String, in target: String) -> Int? {
        var queryIndex = query.startIndex
        var consecutiveBonus = 0
        var lastMatchedIndex: String.Index?

        for targetIndex in target.indices {
            guard queryIndex < query.endIndex else { break }
            if target[targetIndex] == query[queryIndex] {
                if let last = lastMatchedIndex, target.index(after: last) == targetIndex {
                    consecutiveBonus += 10
                }
                lastMatchedIndex = targetIndex
                queryIndex = query.index(after: queryIndex)
            }
        }

        return queryIndex == query.endIndex ? consecutiveBonus : nil
    }
}

// MARK: - Static

extension Tool {
    public static let fileSearch = Tool(FileSearchTool())
}
