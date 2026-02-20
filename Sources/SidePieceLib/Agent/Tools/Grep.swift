//
//  Grep.swift
//  SidePiece
//

import Foundation

public struct GrepTool: TypedTool {
    public let name = "grep"
    public let description =
        "A powerful ripgrep-based search tool for exact symbol and string matching. " +
        "Supports full regex syntax, respects .gitignore, and offers multiple output modes. " +
        "Ideal for finding specific identifiers, function calls, or text patterns."

    // MARK: - Input

    public struct Input: ToolInput {
        public let pattern: String
        public let path: String?
        public let outputMode: String?
        public let afterContext: Int?
        public let beforeContext: Int?
        public let context: Int?
        public let type: String?
        public let glob: String?

        public static var schema: JSONValue {
            .objectSchema(
                properties: [
                    "pattern": .stringProperty(
                        description: "Regular expression pattern to search for"
                    ),
                    "path": .stringProperty(
                        description: "File or directory to search in, relative to the project root or absolute. Defaults to the project root."
                    ),
                    "output_mode": .stringProperty(
                        description: "Output mode: \"content\" shows matching lines, \"files_with_matches\" shows only file paths, \"count\" shows match counts per file. Defaults to \"files_with_matches\".",
                        cases: ["content", "files_with_matches", "count"]
                    ),
                    "after_context": .intProperty(
                        description: "Number of lines to show after each match."
                    ),
                    "before_context": .intProperty(
                        description: "Number of lines to show before each match."
                    ),
                    "context": .intProperty(
                        description: "Number of lines to show before and after each match."
                    ),
                    "type": .stringProperty(
                        description: "Filter files by type (e.g. \"swift\", \"py\", \"js\"). Uses ripgrep's built-in type definitions."
                    ),
                    "glob": .stringProperty(
                        description: "Filter files by glob pattern (e.g. \"*.swift\", \"**/*.{ts,tsx}\")."
                    ),
                ],
                required: ["pattern"]
            )
        }
    }

    // MARK: - Output

    public struct Output: Encodable, ToolOutput {
        public let output: String
        public let outputMode: String
        public let matchesFound: Bool
    }

    // MARK: - Execute

    public func execute(_ input: Input, projectURL: URL) async throws -> Output {
        let searchPath: String
        if let path = input.path, !path.isEmpty {
            if path.hasPrefix("/") {
                searchPath = URL(fileURLWithPath: path).standardizedFileURL.path
            } else {
                searchPath = projectURL.appendingPathComponent(path).standardizedFileURL.path
            }
        } else {
            searchPath = projectURL.path
        }

        let resolvedOutputMode = input.outputMode ?? "files_with_matches"

        var rgArgs: [String] = ["--no-heading"]

        switch resolvedOutputMode {
        case "files_with_matches":
            rgArgs.append("--files-with-matches")
        case "count":
            rgArgs.append("--count")
        default: // "content"
            rgArgs.append("--line-number")
        }

        if let c = input.context {
            rgArgs += ["--context", "\(c)"]
        } else {
            if let a = input.afterContext { rgArgs += ["--after-context", "\(a)"] }
            if let b = input.beforeContext { rgArgs += ["--before-context", "\(b)"] }
        }

        if let t = input.type { rgArgs += ["--type", t] }
        if let g = input.glob { rgArgs += ["--glob", g] }

        rgArgs += ["--", input.pattern, searchPath]

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["rg"] + rgArgs

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        // rg exits 0 = matches found, 1 = no matches (not an error), 2 = error
        if process.terminationStatus == 2 {
            let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let errMsg = String(data: errData, encoding: .utf8) ?? "Unknown error"
            throw ToolExecutionError.unknown(
                "ripgrep error: \(errMsg.trimmingCharacters(in: .whitespacesAndNewlines))"
            )
        }

        let outputData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let outputText = String(data: outputData, encoding: .utf8) ?? ""

        return Output(
            output: outputText,
            outputMode: resolvedOutputMode,
            matchesFound: process.terminationStatus == 0
        )
    }
}

// MARK: - Static

extension Tool {
    public static let grep = Tool(GrepTool())
}
