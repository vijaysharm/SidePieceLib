//
//  ReadFile.swift
//  SidePiece
//

import Foundation

// MARK: - Tool

public struct ReadFileTool: TypedTool {
    public let name = "read_file"
    public let description =
        "Read the contents of a file from the project directory. " +
        "Returns the file content as text with line numbers, or base64 data for image files."

    // MARK: - Input

    public struct Input: ToolInput {
        /// Path to the file, relative to the project root or absolute.
        public let targetFile: String
        /// 1-based line number to start reading from. Defaults to 1 when absent.
        public let offset: Int?
        /// Maximum number of lines to read. Reads the entire file when absent.
        public let limit: Int?

        public static var schema: JSONValue {
            .objectSchema(
                properties: [
                    "target_file": .stringProperty(
                        description: "The path of the file to read, relative to the project root or absolute"
                    ),
                    "offset": .intProperty(
                        description: "The 1-based line number to start reading from. Defaults to 1."
                    ),
                    "limit": .intProperty(
                        description: "The maximum number of lines to read. If not specified, reads the entire file."
                    ),
                ],
                required: ["target_file"]
            )
        }
    }

    // MARK: - Output

    public enum Output: ToolOutput {
        case text(content: String, totalLines: Int, linesRead: Int)
        case image(mediaType: String, data: String)

        public var toolResultString: String {
            get throws {
                switch self {
                case let .text(content, totalLines, linesRead):
                    let result: JSONValue = .object([
                        "content":     .string(content),
                        "total_lines": .int(totalLines),
                        "lines_read":  .int(linesRead),
                    ])
                    return try result.toJSONString()

                case let .image(mediaType, data):
                    let result: JSONValue = .object([
                        "media_type": .string(mediaType),
                        "data":       .string(data),
                    ])
                    return try result.toJSONString()
                }
            }
        }
    }
    
    public func execute(_ input: Input, projectURL: URL) async throws -> Output {
        let fileURL: URL
        if input.targetFile.hasPrefix("/") {
            fileURL = URL(fileURLWithPath: input.targetFile).standardizedFileURL
        } else {
            fileURL = projectURL.appendingPathComponent(input.targetFile).standardizedFileURL
        }

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw ToolExecutionError.unknown("File not found: \(fileURL.path)")
        }

        let data = try Data(contentsOf: fileURL)

        if let mediaType = MediaTypeDetector.detect(from: data) {
            return .image(mediaType: mediaType, data: data.base64EncodedString())
        }

        guard let content = String(data: data, encoding: .utf8) else {
            throw ToolExecutionError.unknown("File is not valid UTF-8 text: \(fileURL.path)")
        }

        let allLines = content.components(separatedBy: "\n")
        let totalLines = allLines.count
        let startIndex = max(0, (input.offset ?? 1) - 1)
        let endIndex = input.limit.map { min(totalLines, startIndex + $0) } ?? totalLines

        guard startIndex < totalLines else {
            return .text(content: "", totalLines: totalLines, linesRead: 0)
        }

        let numberedContent = allLines[startIndex..<endIndex]
            .enumerated()
            .map { index, line in "\(startIndex + index + 1)\t\(line)" }
            .joined(separator: "\n")

        return .text(content: numberedContent, totalLines: totalLines, linesRead: endIndex - startIndex)
    }
}

// MARK: - Static

extension Tool {
    public static let readFile = Tool(ReadFileTool())
}
