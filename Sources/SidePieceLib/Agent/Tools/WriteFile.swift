//
//  WriteFile.swift
//  SidePiece
//

import Foundation

// MARK: - Tool

public struct WriteFileTool: TypedTool {
    public let name = "write_file"
    public let safetyLevel: ToolSafetyLevel = .supervised
    public let description =
        "Write content to a file. Creates the file (and any intermediate directories) " +
        "if it doesn't exist, or overwrites the file if it does. " +
        "Use this for creating new files or completely rewriting existing ones. " +
        "For partial edits to existing files, prefer the edit_file tool instead."

    // MARK: - Input

    public struct Input: ToolInput {
        /// Path to the file, relative to the project root or absolute.
        public let targetFile: String
        /// The full content to write to the file.
        public let content: String

        public static var schema: JSONValue {
            .objectSchema(
                properties: [
                    "target_file": .stringProperty(
                        description: "The path of the file to write, relative to the project root or absolute"
                    ),
                    "content": .stringProperty(
                        description: "The content to write to the file"
                    ),
                ],
                required: ["target_file", "content"]
            )
        }
    }

    // MARK: - Output

    public struct Output: Encodable, ToolOutput {
        public let path: String
        public let bytesWritten: Int
        public let created: Bool
    }

    // MARK: - Execute

    public func execute(_ input: Input, projectURL: URL) async throws -> Output {
        let resolved = input.targetFile.hasPrefix("/")
            ? URL(fileURLWithPath: input.targetFile)
            : projectURL.appendingPathComponent(input.targetFile)

        let path = resolved.path
        let existed = FileManager.default.fileExists(atPath: path)

        // Create intermediate directories if needed
        let parentDir = resolved.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parentDir.path) {
            do {
                try FileManager.default.createDirectory(
                    at: parentDir,
                    withIntermediateDirectories: true
                )
            } catch {
                throw ToolExecutionError.executionFailed(
                    message: "Failed to create directory \(parentDir.path): \(error.localizedDescription)"
                )
            }
        }

        guard let data = input.content.data(using: .utf8) else {
            throw ToolExecutionError.executionFailed(message: "Content is not valid UTF-8")
        }

        do {
            try data.write(to: resolved, options: .atomic)
        } catch {
            throw ToolExecutionError.executionFailed(
                message: "Failed to write file \(path): \(error.localizedDescription)"
            )
        }

        return Output(path: path, bytesWritten: data.count, created: !existed)
    }
}

// MARK: - Tool Extension

extension Tool {
    public static let writeFile = Tool(WriteFileTool())
}
