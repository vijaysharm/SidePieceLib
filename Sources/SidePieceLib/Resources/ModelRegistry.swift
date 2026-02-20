//
//  ModelRegistry.swift
//  SidePiece
//
import Foundation

public enum ModelRegistry {

    /// The JSON is an object whose keys are provider IDs (e.g. "anthropic").
    /// Those keys are outside your control, so model them as dictionary keys.
    public struct LLMRegistry: Codable, Sendable {
        public var providers: [ProviderID: Provider]

        public init(providers: [ProviderID: Provider]) {
            self.providers = providers
        }

        // Decode/encode as a single keyed container with dynamic keys.
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(
                keyedBy: DynamicCodingKey.self
            )
            var result: [ProviderID: Provider] = [:]
            for key in container.allKeys {
                let provider = try container.decode(Provider.self, forKey: key)
                result[ProviderID(rawValue: key.stringValue)] = provider
            }
            self.providers = result
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: DynamicCodingKey.self)
            for (id, provider) in providers {
                try container.encode(
                    provider,
                    forKey: DynamicCodingKey(id.rawValue)
                )
            }
        }
    }

    // MARK: - Provider

    public struct Provider: Codable, Sendable, Hashable {
        public let id: ProviderID
        public let env: [EnvVar]
        public let npm: NpmPackage
        public let name: String
        public let doc: URL

        /// The keys under "models" are not stable / not known at compile time.
        /// Keep them as dictionary keys, but strongly type the values.
        public let models: [ModelID: Model]

        public init(
            id: ProviderID,
            env: [EnvVar],
            npm: NpmPackage,
            name: String,
            doc: URL,
            models: [ModelID: Model]
        ) {
            self.id = id
            self.env = env
            self.npm = npm
            self.name = name
            self.doc = doc
            self.models = models
        }

        private enum CodingKeys: String, CodingKey {
            case id, env, npm, name, doc, models
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.id = try c.decode(ProviderID.self, forKey: .id)
            self.env = try c.decode([EnvVar].self, forKey: .env)
            self.npm = try c.decode(NpmPackage.self, forKey: .npm)
            self.name = try c.decode(String.self, forKey: .name)
            self.doc = try c.decode(URL.self, forKey: .doc)

            // Decode "models" with dynamic keys
            let modelsContainer = try c.nestedContainer(
                keyedBy: DynamicCodingKey.self,
                forKey: .models
            )
            var models: [ModelID: Model] = [:]
            for key in modelsContainer.allKeys {
                let model = try modelsContainer.decode(Model.self, forKey: key)
                models[ModelID(rawValue: key.stringValue)] = model
            }
            self.models = models
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(id, forKey: .id)
            try c.encode(env, forKey: .env)
            try c.encode(npm, forKey: .npm)
            try c.encode(name, forKey: .name)
            try c.encode(doc, forKey: .doc)

            var modelsContainer = c.nestedContainer(
                keyedBy: DynamicCodingKey.self,
                forKey: .models
            )
            for (id, model) in models {
                try modelsContainer.encode(
                    model,
                    forKey: DynamicCodingKey(id.rawValue)
                )
            }
        }
    }

    // MARK: - Model

    public struct Model: Codable, Sendable, Hashable {
        public let id: ModelID
        public let name: String
        public let family: ModelFamily?

        public let attachment: Bool
        public let reasoning: Bool
        public let toolCall: Bool
        public let temperature: Bool?

        /// Dates are strings in the JSON. Parse into a strong type so you don't
        /// end up doing string comparisons everywhere.
        public let knowledge: YMDDate?
        public let releaseDate: YMDDate
        public let lastUpdated: YMDDate

        public let modalities: Modalities
        public let openWeights: Bool
        public let cost: Cost?
        public let limit: Limit

        private enum CodingKeys: String, CodingKey {
            case id, name, family
            case attachment, reasoning
            case toolCall = "tool_call"
            case temperature
            case knowledge
            case releaseDate = "release_date"
            case lastUpdated = "last_updated"
            case modalities
            case openWeights = "open_weights"
            case cost
            case limit
        }
    }

    public struct Modalities: Codable, Sendable, Hashable {
        public let input: [Modality]
        public let output: [Modality]
    }

    /// Stronger than String, but still tolerant: if a new modality appears,
    /// you keep it as `.other("...")` without failing decoding.
    public enum Modality: Codable, Sendable, Hashable {
        case text
        case image
        case pdf
        case other(String)

        public init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            switch raw {
            case "text": self = .text
            case "image": self = .image
            case "pdf": self = .pdf
            default: self = .other(raw)
            }
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.singleValueContainer()
            switch self {
            case .text: try c.encode("text")
            case .image: try c.encode("image")
            case .pdf: try c.encode("pdf")
            case .other(let s): try c.encode(s)
            }
        }
    }

    public struct Cost: Codable, Sendable, Hashable {
        public let input: Decimal
        public let output: Decimal
        public let cacheRead: Decimal?
        public let cacheWrite: Decimal?

        private enum CodingKeys: String, CodingKey {
            case input, output
            case cacheRead = "cache_read"
            case cacheWrite = "cache_write"
        }
    }

    public struct Limit: Codable, Sendable, Hashable {
        public let context: Int
        public let output: Int
    }

    // MARK: - Strong ID wrappers (avoid "stringly typed" access)

    public struct ProviderID: RawRepresentable, Codable, Sendable, Hashable,
        ExpressibleByStringLiteral
    {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public init(stringLiteral value: StringLiteralType) {
            self.rawValue = value
        }
    }

    public struct ModelID: RawRepresentable, Codable, Sendable, Hashable,
        ExpressibleByStringLiteral
    {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public init(stringLiteral value: StringLiteralType) {
            self.rawValue = value
        }
    }

    public struct NpmPackage: RawRepresentable, Codable, Sendable, Hashable,
        ExpressibleByStringLiteral
    {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public init(stringLiteral value: StringLiteralType) {
            self.rawValue = value
        }
    }

    public struct EnvVar: RawRepresentable, Codable, Sendable, Hashable,
        ExpressibleByStringLiteral
    {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public init(stringLiteral value: StringLiteralType) {
            self.rawValue = value
        }
    }

    public struct ModelFamily: RawRepresentable, Codable, Sendable, Hashable,
        ExpressibleByStringLiteral
    {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public init(stringLiteral value: StringLiteralType) {
            self.rawValue = value
        }
    }

    // MARK: - Date type (YYYY-MM-DD)

    /// A strong type for "YYYY-MM-DD" values.
    /// - Codable from a string
    /// - Comparable if you want ordering later
    public struct YMDDate: Codable, Sendable, Hashable, Comparable {
        public let year: Int
        public let month: Int
        public let day: Int

        public init(year: Int, month: Int, day: Int) {
            self.year = year
            self.month = month
            self.day = day
        }

        public init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            // Very strict parse; you can relax if you need.
            let parts = raw.split(separator: "-")
            guard parts.count >= 2,
                let y = Int(parts[0]),
                let m = Int(parts[1])
            else {
                throw DecodingError.dataCorrupted(
                    .init(
                        codingPath: decoder.codingPath,
                        debugDescription: "Invalid YMDDate: \(raw)"
                    )
                )
            }
            self.year = y
            self.month = m
            self.day = parts.count == 3 ? Int(parts[2]) ?? 1 : 1
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.singleValueContainer()
            let s = String(format: "%04d-%02d-%02d", year, month, day)
            try c.encode(s)
        }

        public static func < (lhs: YMDDate, rhs: YMDDate) -> Bool {
            (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
        }
    }

    // MARK: - DynamicCodingKey

    /// Standard helper for decoding dictionaries with unknown keys.
    public struct DynamicCodingKey: CodingKey, Hashable {
        public var stringValue: String
        public var intValue: Int? { nil }

        public init(_ string: String) { self.stringValue = string }
        public init?(stringValue: String) { self.stringValue = stringValue }
        public init?(intValue: Int) { return nil }
    }
}
