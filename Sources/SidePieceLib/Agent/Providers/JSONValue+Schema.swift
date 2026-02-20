//
//  JSONValue+Schema.swift
//  SidePiece
//
//  Ergonomic helpers for constructing JSON Schema objects used in ToolInput.schema.
//  These mirror the subset of JSON Schema that LLM tool definitions support.
//

// MARK: - Schema Builders

extension JSONValue {

    // MARK: Object

    /// Builds a JSON Schema `"object"` node with named properties and an optional
    /// required-field list.
    ///
    /// ```swift
    /// static var schema: JSONValue {
    ///     .objectSchema(
    ///         properties: [
    ///             "query":    .stringProperty(description: "The search query"),
    ///             "max_hits": .intProperty(description: "Maximum results"),
    ///         ],
    ///         required: ["query"]
    ///     )
    /// }
    /// ```
    public static func objectSchema(
        properties: [String: JSONValue],
        required: [String] = []
    ) -> JSONValue {
        var schema: [String: JSONValue] = [
            "type": .string("object"),
            "properties": .object(properties),
        ]
        if !required.isEmpty {
            schema["required"] = .array(required.map { .string($0) })
        }
        return .object(schema)
    }

    // MARK: Primitive Properties

    /// Builds a JSON Schema `"string"` property node.
    ///
    /// - Parameters:
    ///   - description: Shown to the LLM to describe what the field is for.
    ///   - cases: Optional enumeration of allowed values.
    public static func stringProperty(
        description: String,
        cases: [String]? = nil
    ) -> JSONValue {
        var node: [String: JSONValue] = [
            "type": .string("string"),
            "description": .string(description),
        ]
        if let cases {
            node["enum"] = .array(cases.map { .string($0) })
        }
        return .object(node)
    }

    /// Builds a JSON Schema `"integer"` property node.
    public static func intProperty(description: String) -> JSONValue {
        .object([
            "type": .string("integer"),
            "description": .string(description),
        ])
    }

    /// Builds a JSON Schema `"number"` property node (floating-point).
    public static func numberProperty(description: String) -> JSONValue {
        .object([
            "type": .string("number"),
            "description": .string(description),
        ])
    }

    /// Builds a JSON Schema `"boolean"` property node.
    public static func boolProperty(description: String) -> JSONValue {
        .object([
            "type": .string("boolean"),
            "description": .string(description),
        ])
    }

    // MARK: Composite Properties

    /// Builds a JSON Schema `"array"` property node whose items conform to `itemSchema`.
    ///
    /// ```swift
    /// "tags": .arrayProperty(description: "Labels to apply", items: .stringProperty(description: "A label"))
    /// ```
    public static func arrayProperty(
        description: String,
        items: JSONValue
    ) -> JSONValue {
        .object([
            "type": .string("array"),
            "description": .string(description),
            "items": items,
        ])
    }

    /// Builds a JSON Schema `"object"` property node (for nested objects).
    ///
    /// ```swift
    /// "range": .objectProperty(
    ///     description: "Line range to read",
    ///     properties: [
    ///         "start": .intProperty(description: "Start line (1-based)"),
    ///         "end":   .intProperty(description: "End line (inclusive)"),
    ///     ],
    ///     required: ["start", "end"]
    /// )
    /// ```
    public static func objectProperty(
        description: String,
        properties: [String: JSONValue],
        required: [String] = []
    ) -> JSONValue {
        var node: [String: JSONValue] = [
            "type": .string("object"),
            "description": .string(description),
            "properties": .object(properties),
        ]
        if !required.isEmpty {
            node["required"] = .array(required.map { .string($0) })
        }
        return .object(node)
    }
}
