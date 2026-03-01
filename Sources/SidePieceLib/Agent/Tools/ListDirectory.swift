//
//  ListDirectory.swift
//  SidePiece
//

import Darwin
import Foundation

// MARK: - Tool

public struct ListDirectoryTool: TypedTool {
    public let name = "list_dir"
    public let description =
        "Lists files and directories in a given path. Does not display dot-files and " +
        "dot-directories by default. Supports filtering with glob patterns to ignore " +
        "specific files or directories."

    // MARK: - Input

    public struct Input: ToolInput {
        /// Path to the directory to list, relative to the project root or absolute.
        public let targetDirectory: String
        /// Glob patterns (e.g. `"*.log"`, `"node_modules"`) to exclude from results.
        public let ignoreGlobs: [String]?

        public static var schema: JSONValue {
            .objectSchema(
                properties: [
                    "target_directory": .stringProperty(
                        description: "Path to directory to list (relative or absolute)"
                    ),
                    "ignore_globs": .arrayProperty(
                        description: "Array of glob patterns to ignore",
                        items: .stringProperty(description: "A glob pattern (e.g. \"*.log\", \"node_modules\")")
                    ),
                ],
                required: ["target_directory"]
            )
        }
    }

    // MARK: - Output

    public struct Output: Encodable, ToolOutput {
        public struct Entry: Encodable {
            public let name: String
            /// `"file"` or `"directory"`.
            public let type: String
            /// Path relative to the project root (or absolute if outside the project).
            public let path: String
        }

        public let entries: [Entry]
    }

    // MARK: - Execute

    public func execute(_ input: Input, projectURL: URL) async throws -> Output {
        let directoryURL: URL
        if input.targetDirectory.hasPrefix("/") {
            directoryURL = URL(fileURLWithPath: input.targetDirectory).standardizedFileURL
        } else {
            directoryURL = projectURL.appendingPathComponent(input.targetDirectory).standardizedFileURL
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw ToolExecutionError.directoryNotFound(path: directoryURL.path)
        }

        let contents = try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        )

        // Directories first, then files; both groups sorted alphabetically.
        let sortedContents = contents.sorted { lhs, rhs in
            let lhsIsDir = (try? lhs.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let rhsIsDir = (try? rhs.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if lhsIsDir != rhsIsDir { return lhsIsDir }
            return lhs.lastPathComponent < rhs.lastPathComponent
        }

        let ignoreGlobs = input.ignoreGlobs ?? []
        let projectPath = projectURL.path

        let entries: [Output.Entry] = sortedContents.compactMap { url in
            let name = url.lastPathComponent
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false

            if ignoreGlobs.contains(where: { fnmatch($0, name, 0) == 0 }) {
                return nil
            }

            let relativePath: String
            if url.path.hasPrefix(projectPath + "/") {
                relativePath = String(url.path.dropFirst(projectPath.count + 1))
            } else {
                relativePath = url.path
            }

            return Output.Entry(name: name, type: isDir ? "directory" : "file", path: relativePath)
        }

        return Output(entries: entries)
    }
}

// MARK: - Static

extension Tool {
    public static let listDirectory = Tool(ListDirectoryTool())
}
