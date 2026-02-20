//
//  JSONValue.swift
//  SidePiece
//
//  Strongly-typed JSON value (no `[String: Any]`).
//

import Foundation

public enum JSONValue: Sendable, Hashable, Codable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    // MARK: - Convenience accessors

    public var stringValue: String? {
        if case let .string(v) = self { return v }
        return nil
    }

    public var intValue: Int? {
        if case let .int(v) = self { return v }
        return nil
    }

    public var doubleValue: Double? {
        switch self {
        case .double(let v): return v
        case .int(let v): return Double(v)
        default: return nil
        }
    }

    public var boolValue: Bool? {
        if case let .bool(v) = self { return v }
        return nil
    }

    public var arrayValue: [JSONValue]? {
        if case let .array(v) = self { return v }
        return nil
    }

    public var objectValue: [String: JSONValue]? {
        if case let .object(v) = self { return v }
        return nil
    }

    // MARK: - Codable

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let b = try? container.decode(Bool.self) {
            self = .bool(b)
        } else if let i = try? container.decode(Int.self) {
            self = .int(i)
        } else if let d = try? container.decode(Double.self) {
            self = .double(d)
        } else if let s = try? container.decode(String.self) {
            self = .string(s)
        } else if let a = try? container.decode([JSONValue].self) {
            self = .array(a)
        } else if let o = try? container.decode([String: JSONValue].self) {
            self = .object(o)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSONValue"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let b):
            try container.encode(b)
        case .int(let i):
            try container.encode(i)
        case .double(let d):
            try container.encode(d)
        case .string(let s):
            try container.encode(s)
        case .array(let a):
            try container.encode(a)
        case .object(let o):
            try container.encode(o)
        }
    }

    // MARK: - Helpers

    public static func parse(jsonString: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(jsonString.utf8))
    }

    public func toJSONString(pretty: Bool = false) throws -> String {
        let encoder = JSONEncoder()
        if pretty { encoder.outputFormatting = [.prettyPrinted, .sortedKeys] }
        let data = try encoder.encode(self)
        return String(decoding: data, as: UTF8.self)
    }
}
