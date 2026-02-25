//
//  TypedTool.swift
//  SidePiece
//
//  Protocol-oriented typed tool system. Provides compile-time type safety for
//  tool inputs and outputs, with JSON encoding/decoding handled by the framework
//  rather than by each tool implementation.
//

import Foundation
import Dependencies
import DependenciesMacros

// MARK: - ToolInput

/// A protocol for typed tool inputs.
///
/// Conforming types are automatically decoded from the raw JSON string sent by
/// the LLM. The decoder uses `.convertFromSnakeCase`, so LLM snake_case keys
/// (e.g. `target_file`) map directly to camelCase Swift properties (e.g.
/// `targetFile`) without requiring manual `CodingKeys`.
///
/// Conforming types must also declare a `schema` — the JSON Schema object
/// that is sent to the LLM as part of the tool definition.
public protocol ToolInput: Decodable {
    /// The JSON Schema object describing the accepted parameters for this tool.
    /// Use the `JSONValue` schema builder helpers to construct it ergonomically.
    static var schema: JSONValue { get }
}

// MARK: - ToolOutput

/// A protocol for typed tool outputs.
///
/// Conforming types are serialized to a plain `String` that is returned to the
/// LLM as the tool result. For most cases, conforming to `Encodable` as well
/// gains the default JSON serialization implementation for free.
public protocol ToolOutput {
    /// Serializes the output to a string for the LLM tool result.
    var toolResultString: String { get throws }
}

/// Provides automatic JSON serialization for `Encodable` ToolOutput types.
///
/// Properties are encoded with `.convertToSnakeCase`, so camelCase Swift
/// property names (e.g. `totalLines`) become snake_case JSON keys
/// (e.g. `total_lines`) automatically.
extension ToolOutput where Self: Encodable {
    public var toolResultString: String {
        get throws {
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            let data = try encoder.encode(self)
            return String(data: data, encoding: .utf8) ?? "{}"
        }
    }
}

// MARK: - TypedTool

/// A type-safe tool with strongly-typed `Input` and `Output`.
///
/// Implement this protocol instead of constructing a raw `Tool` directly.
/// The framework handles all JSON plumbing: decoding the LLM's raw JSON
/// argument string into `Input`, and serializing `Output` back to a string.
/// Your `execute` implementation works exclusively with concrete Swift types.
///
/// ## Example
///
/// ```swift
/// struct SearchInput: ToolInput {
///     let query: String
///     let maxResults: Int?
///
///     static var schema: JSONValue {
///         .objectSchema(
///             properties: [
///                 "query":       .stringProperty(description: "The search query"),
///                 "max_results": .intProperty(description: "Maximum results to return"),
///             ],
///             required: ["query"]
///         )
///     }
/// }
///
/// struct SearchOutput: Encodable, ToolOutput {
///     let results: [String]  // encoded as "results"
///     let totalCount: Int    // encoded as "total_count"
/// }
///
/// struct SearchTool: TypedTool {
///     static let name        = "search"
///     static let description = "Search the project for matching content."
///
///     func execute(_ input: SearchInput, projectURL: URL) async throws -> SearchOutput {
///         // input.query and input.maxResults are already the right Swift types
///         SearchOutput(results: ["..."], totalCount: 1)
///     }
/// }
///
/// extension Tool {
///     public static let search = SearchTool().erased()
/// }
/// ```
public protocol TypedTool: Sendable {
    associatedtype Input: ToolInput
    associatedtype Output: ToolOutput

    /// The unique name used to identify this tool (e.g. `"read_file"`).
    /// Must match the value the LLM will use when calling the tool.
    var name: String { get }

    /// A human-readable description sent to the LLM explaining what the tool does.
    var description: String { get }

    /// Given the decoded input from the LLM, produces the interaction specification.
    /// Defaults to `.permission` (the standard Allow/Deny gate).
    ///
    /// Override for interactive tools to return `.textInput`, `.choice`,
    /// `.questionnaire`, or `.confirmation`. The returned interaction's
    /// `argumentKey` tells the framework where to merge the user's response
    /// into the arguments JSON before decoding the final `Input`.
    func resolveInteraction(for input: Input) -> ToolInteraction

    /// Executes the tool with decoded, strongly-typed inputs.
    ///
    /// For interactive tools, the `Input` will contain both the LLM-provided
    /// fields and the user's response (merged under the interaction's `argumentKey`).
    ///
    /// - Parameters:
    ///   - input: The decoded input struct — no JSON parsing needed.
    ///   - projectURL: The root directory of the current project.
    /// - Returns: A strongly-typed output value that will be serialized for the LLM.
    func execute(_ input: Input, projectURL: URL) async throws -> Output
}

extension TypedTool {
    /// Default interaction: simple permission gate.
    public func resolveInteraction(for input: Input) -> ToolInteraction { .permission }

    /// The `ToolDefinition` derived from this tool's `name`, `description`, and
    /// `Input.schema`. Passed to the LLM in `LLMRequestOptions.tools`.
    public var definition: ToolDefinition {
        ToolDefinition(
            name: name,
            description: description,
            parameters: Input.schema
        )
    }
}

extension Tool {
    /// Creates an untyped `Tool` from any `TypedTool`.
    ///
    /// This initializer handles all the JSON plumbing so tool implementations
    /// never need to touch raw strings:
    /// 1. Decodes the raw JSON argument string into `T.Input` (snake_case → camelCase).
    /// 2. Calls `typedTool.execute(_:projectURL:)` with the strongly-typed input.
    /// 3. Serializes `T.Output` back to a string for the LLM.
    ///
    /// For interactive tools, `resolveInteraction` decodes the arguments to
    /// produce the interaction specification. If decoding fails, falls back
    /// to `.permission`.
    public init<T: TypedTool>(_ typedTool: T) {
        self.init(
            definition: typedTool.definition,
            resolveInteraction: { arguments in
                @Dependency(\.jsonCoder) var jsonCoder
                guard let data = arguments.data(using: .utf8),
                      let input = try? jsonCoder.decode(T.Input.self, from: data, decoding: .convertFromSnakeCase)
                else {
                    return .permission
                }
                return typedTool.resolveInteraction(for: input)
            },
            execute: { arguments, projectURL in
                @Dependency(\.jsonCoder) var jsonCoder
                guard let data = arguments.data(using: .utf8) else {
                    throw ToolExecutionError.unknown(
                        "Invalid UTF-8 in tool arguments for '\(typedTool.name)'"
                    )
                }
                let input = try jsonCoder.decode(T.Input.self, from: data, decoding: .convertFromSnakeCase)
                let output = try await typedTool.execute(input, projectURL: projectURL)
                return try output.toolResultString
            }
        )
    }
}
