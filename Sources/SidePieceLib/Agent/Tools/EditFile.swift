//
//  EditFile.swift
//  SidePiece
//

import Foundation

// MARK: - Tool

public struct EditFileTool: TypedTool {
    public let name = "edit_file"
    public let safetyLevel: ToolSafetyLevel = .supervised
    public let description =
        "Make targeted edits to an existing file using search-and-replace. " +
        "Each edit finds an exact match of old_string in the file and replaces it " +
        "with new_string. The old_string must match exactly (including whitespace " +
        "and indentation). For creating new files, use write_file instead."

    // MARK: - Input

    public struct Input: ToolInput {
        /// Path to the file, relative to the project root or absolute.
        public let targetFile: String
        /// An array of edit operations to apply sequentially.
        public let edits: [EditOperation]

        public struct EditOperation: Decodable, Sendable {
            public let oldString: String
            public let newString: String
        }

        public static var schema: JSONValue {
            .objectSchema(
                properties: [
                    "target_file": .stringProperty(
                        description: "The path of the file to edit, relative to the project root or absolute"
                    ),
                    "edits": .arrayProperty(
                        description: "Array of edit operations to apply",
                        items: .objectSchema(
                            properties: [
                                "old_string": .stringProperty(
                                    description: "The exact text to find in the file (must match exactly, including whitespace)"
                                ),
                                "new_string": .stringProperty(
                                    description: "The replacement text"
                                ),
                            ],
                            required: ["old_string", "new_string"]
                        )
                    ),
                ],
                required: ["target_file", "edits"]
            )
        }
    }

    // MARK: - Output

    public struct Output: Encodable, ToolOutput {
        public let path: String
        public let editsApplied: Int
    }

    // MARK: - Execute

    public func execute(_ input: Input, projectURL: URL) async throws -> Output {
        let resolved = input.targetFile.hasPrefix("/")
            ? URL(fileURLWithPath: input.targetFile)
            : projectURL.appendingPathComponent(input.targetFile)

        let path = resolved.path

        guard FileManager.default.fileExists(atPath: path) else {
            throw ToolExecutionError.fileNotFound(path: path)
        }

        var content: String
        do {
            content = try String(contentsOf: resolved, encoding: .utf8)
        } catch {
            throw ToolExecutionError.executionFailed(
                message: "Failed to read file \(path): \(error.localizedDescription)"
            )
        }

        var appliedCount = 0
        for edit in input.edits {
            guard let range = content.range(of: edit.oldString) else {
                throw ToolExecutionError.executionFailed(
                    message: "Could not find exact match for old_string in \(input.targetFile). " +
                        "Make sure the text matches exactly, including whitespace and indentation."
                )
            }
            content.replaceSubrange(range, with: edit.newString)
            appliedCount += 1
        }

        guard let data = content.data(using: .utf8) else {
            throw ToolExecutionError.executionFailed(message: "Edited content is not valid UTF-8")
        }

        do {
            try data.write(to: resolved, options: .atomic)
        } catch {
            throw ToolExecutionError.executionFailed(
                message: "Failed to write file \(path): \(error.localizedDescription)"
            )
        }

        return Output(path: path, editsApplied: appliedCount)
    }
}

// MARK: - Tool Extension

extension Tool {
    public static let editFile = Tool(EditFileTool())
}
