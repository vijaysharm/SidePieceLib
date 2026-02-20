//
//  CodebaseFileSearch.swift
//  SidePiece
//

import Foundation

// MARK: - Tool

public struct CodebaseFileSearchTool: TypedTool {
    public let name = "codebase_search"
    public let description =
        "Semantic search that finds code by meaning, not exact text. " +
        "Perfect for exploring unfamiliar codebases and answering \"how\", " +
        "\"where\", and \"what\" questions about code behavior. " +
        "Works best with complete questions rather than keywords."

    // MARK: - Input

    public struct Input: ToolInput {
        /// A complete question about what you want to understand.
        public let query: String
        /// Directory paths to limit search scope (empty for whole repo).
        public let targetDirectories: [String]
        /// Why this search is being performed.
        public let explanation: String

        public static var schema: JSONValue {
            .objectSchema(
                properties: [
                    "query": .stringProperty(
                        description: "A complete question about what you want to understand"
                    ),
                    "target_directories": .arrayProperty(
                        description: "Directory paths to limit search scope ([] for whole repo)",
                        items: .stringProperty(description: "A directory path")
                    ),
                    "explanation": .stringProperty(
                        description: "Why this search is being performed"
                    ),
                ],
                required: ["query", "target_directories", "explanation"]
            )
        }
    }

    // MARK: - Output

    public struct Output: ToolOutput {
        public let query: String
        public let results: [Match]

        public struct Match {
            public let file: String
            public let line: Int
            public let content: String
            public let matchCount: Int
        }

        public var toolResultString: String {
            get throws {
                let result: JSONValue = .object([
                    "query": .string(query),
                    "results": .array(results.map { match in
                        .object([
                            "file":        .string(match.file),
                            "line":        .int(match.line),
                            "content":     .string(match.content),
                            "match_count": .int(match.matchCount),
                        ])
                    }),
                    "total_results": .int(results.count),
                ])
                return try result.toJSONString()
            }
        }
    }

    // MARK: - Execute

    public func execute(_ input: Input, projectURL: URL) async throws -> Output {
        let searchRoots: [URL]
        if input.targetDirectories.isEmpty {
            searchRoots = [projectURL]
        } else {
            searchRoots = input.targetDirectories.map { dir in
                if dir.hasPrefix("/") {
                    return URL(fileURLWithPath: dir).standardizedFileURL
                } else {
                    return projectURL.appendingPathComponent(dir).standardizedFileURL
                }
            }
        }

        let keywords = Self.extractKeywords(from: input.query)

        var results: [Output.Match] = []
        let maxResults = 20

        for root in searchRoots {
            guard FileManager.default.fileExists(atPath: root.path) else { continue }
            let matches = try Self.searchDirectory(
                root, projectRoot: projectURL, keywords: keywords,
                maxResults: maxResults - results.count
            )
            results.append(contentsOf: matches)
            if results.count >= maxResults { break }
        }

        return Output(query: input.query, results: results)
    }

    // MARK: - Private helpers

    private static func extractKeywords(from query: String) -> [String] {
        let stopWords: Set<String> = [
            "a", "an", "the", "is", "are", "was", "were", "be", "been", "being",
            "have", "has", "had", "do", "does", "did", "will", "would", "could",
            "should", "may", "might", "shall", "can", "need", "ought", "used",
            "to", "of", "in", "for", "on", "with", "at", "by", "from", "up",
            "about", "into", "through", "during", "how", "where", "what", "which",
            "who", "whom", "this", "that", "these", "those", "i", "me", "my",
            "we", "our", "you", "your", "he", "she", "it", "they", "them",
            "and", "but", "or", "nor", "so", "yet", "not", "only", "same",
            "than", "too", "very", "just", "because", "as", "until", "while",
            "although", "since", "when", "if", "unless", "however", "therefore",
        ]

        let words = query
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && !stopWords.contains($0) && $0.count > 2 }

        var seen = Set<String>()
        return words.filter { seen.insert($0).inserted }
    }

    private static let sourceFileExtensions: Set<String> = [
        "swift", "m", "h", "mm", "c", "cpp", "cc", "cxx",
        "js", "ts", "jsx", "tsx", "mjs",
        "py", "rb", "go", "rs", "java", "kt", "scala",
        "cs", "fs", "php", "lua",
        "sh", "bash", "zsh",
        "html", "css", "scss", "sass",
        "json", "yaml", "yml", "toml", "xml",
        "sql", "graphql", "proto",
        "md", "txt",
    ]

    private static func searchDirectory(
        _ root: URL, projectRoot: URL, keywords: [String], maxResults: Int
    ) throws -> [Output.Match] {
        guard maxResults > 0 else { return [] }

        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var matches: [Output.Match] = []

        for case let fileURL as URL in enumerator {
            guard matches.count < maxResults else { break }

            let ext = fileURL.pathExtension.lowercased()
            guard sourceFileExtensions.contains(ext) else { continue }

            // Skip files larger than 500 KB
            let attrs = try? fm.attributesOfItem(atPath: fileURL.path)
            if let size = attrs?[.size] as? Int, size > 500_000 { continue }

            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }

            let fileMatches = findMatches(
                in: content, fileURL: fileURL, projectRoot: projectRoot, keywords: keywords
            )
            matches.append(contentsOf: fileMatches.prefix(maxResults - matches.count))
        }

        return matches
    }

    private static func findMatches(
        in content: String, fileURL: URL, projectRoot: URL, keywords: [String]
    ) -> [Output.Match] {
        guard !keywords.isEmpty else { return [] }

        let lines = content.components(separatedBy: "\n")
        var matchingSegments: [Output.Match] = []
        var processedLines = Set<Int>()

        let projectPath = projectRoot.path

        for (lineIndex, line) in lines.enumerated() {
            let lineLower = line.lowercased()
            let matchCount = keywords.filter { lineLower.contains($0) }.count
            guard matchCount > 0 else { continue }

            let contextStart = max(0, lineIndex - 2)
            let contextEnd = min(lines.count - 1, lineIndex + 5)

            // Skip if the anchor line was already included in a prior segment
            guard !processedLines.contains(lineIndex) else { continue }
            (contextStart...contextEnd).forEach { processedLines.insert($0) }

            let numberedContext = lines[contextStart...contextEnd]
                .enumerated()
                .map { idx, l in "\(contextStart + idx + 1)\t\(l)" }
                .joined(separator: "\n")

            let relativePath: String
            if fileURL.path.hasPrefix(projectPath) {
                relativePath = String(fileURL.path.dropFirst(projectPath.count).drop(while: { $0 == "/" }))
            } else {
                relativePath = fileURL.path
            }

            matchingSegments.append(Output.Match(
                file: relativePath,
                line: lineIndex + 1,
                content: numberedContext,
                matchCount: matchCount
            ))

            if matchingSegments.count >= 5 { break }
        }

        return matchingSegments
    }
}

// MARK: - Static

extension Tool {
    public static let codebaseFileSearch = Tool(CodebaseFileSearchTool())
}
