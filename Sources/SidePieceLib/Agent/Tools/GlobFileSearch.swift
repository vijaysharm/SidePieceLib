//
//  GlobFileSearch.swift
//  SidePiece
//

import Darwin
import Foundation

// MARK: - Tool

public struct GlobFileSearchTool: TypedTool {
    public let name = "glob_file_search"
    public let description =
        "Search for files matching a glob pattern. Works fast with codebases of any size " +
        "and returns matching file paths sorted by modification time. Great for finding " +
        "files by extension or naming convention."

    // MARK: - Input

    public struct Input: ToolInput {
        /// Glob pattern to match against file paths (e.g. "*.swift", "**/test_*.ts").
        public let globPattern: String
        /// Directory to search within. Defaults to the project root when absent.
        public let targetDirectory: String?

        public static var schema: JSONValue {
            .objectSchema(
                properties: [
                    "glob_pattern": .stringProperty(
                        description: "Glob pattern like \"*.swift\" or \"**/test_*.ts\""
                    ),
                    "target_directory": .stringProperty(
                        description: "Directory to search within. Defaults to the project root if not specified."
                    ),
                ],
                required: ["glob_pattern"]
            )
        }
    }

    // MARK: - Output

    public struct Output: Encodable, ToolOutput {
        /// Absolute paths of matching files, sorted by modification time (most recent first).
        public let matches: [String]
        public let count: Int
    }

    // MARK: - Execute

    public func execute(_ input: Input, projectURL: URL) async throws -> Output {
        let searchURL: URL
        if let targetDirectory = input.targetDirectory, !targetDirectory.isEmpty {
            if targetDirectory.hasPrefix("/") {
                searchURL = URL(fileURLWithPath: targetDirectory).standardizedFileURL
            } else {
                searchURL = projectURL.appendingPathComponent(targetDirectory).standardizedFileURL
            }
        } else {
            searchURL = projectURL
        }

        guard FileManager.default.fileExists(atPath: searchURL.path) else {
            throw ToolExecutionError.unknown("Directory not found: \(searchURL.path)")
        }

        var matchingFiles: [(path: String, modDate: Date)] = []

        let enumerator = FileManager.default.enumerator(
            at: searchURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        while let fileURL = enumerator?.nextObject() as? URL {
            let isDirectory = (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDirectory { continue }

            // Match against the path relative to the search directory
            let relativePath: String
            let prefix = searchURL.path + "/"
            if fileURL.path.hasPrefix(prefix) {
                relativePath = String(fileURL.path.dropFirst(prefix.count))
            } else {
                relativePath = fileURL.path
            }

            if globMatches(pattern: input.globPattern, path: relativePath) {
                let modDate = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                matchingFiles.append((path: fileURL.path, modDate: modDate))
            }
        }

        matchingFiles.sort { $0.modDate > $1.modDate }

        return Output(
            matches: matchingFiles.map(\.path),
            count: matchingFiles.count
        )
    }

    // MARK: - Glob Matching

    // Splits both the pattern and path on "/" and matches component-by-component,
    // with "**" handled as zero-or-more path components and per-component wildcards
    // ("*", "?", character classes) delegated to fnmatch(3).
    private func globMatches(pattern: String, path: String) -> Bool {
        let patternParts = pattern.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        let pathParts    = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        return globPartsMatch(patternParts: patternParts[...], pathParts: pathParts[...])
    }

    private func globPartsMatch(patternParts: ArraySlice<String>, pathParts: ArraySlice<String>) -> Bool {
        if patternParts.isEmpty { return pathParts.isEmpty }

        let part        = patternParts.first!
        let restPattern = patternParts.dropFirst()

        if part == "**" {
            // Try consuming zero path components
            if globPartsMatch(patternParts: restPattern, pathParts: pathParts) { return true }
            // Try consuming one component and keep "**" in play for more
            if !pathParts.isEmpty {
                return globPartsMatch(patternParts: patternParts, pathParts: pathParts.dropFirst())
            }
            return false
        }

        guard !pathParts.isEmpty else { return false }
        guard fnmatch(part, pathParts.first!, 0) == 0 else { return false }
        return globPartsMatch(patternParts: restPattern, pathParts: pathParts.dropFirst())
    }
}

// MARK: - Static

extension Tool {
    public static let globFileSearch = Tool(GlobFileSearchTool())
}
