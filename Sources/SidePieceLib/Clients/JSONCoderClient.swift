//
//  JSONCoderClient.swift
//  SidePiece
//

import Dependencies
import DependenciesMacros
import Foundation

@DependencyClient
public struct JSONCoderClient: Sendable {
    func decode<T: Decodable>(
        _ type: T.Type,
        from data: Data,
        decoding: JSONDecoder.KeyDecodingStrategy = .useDefaultKeys
    ) throws(DecodingFailedError) -> T {
        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = decoding
            return try decoder.decode(type, from: data)
        } catch let error as DecodingError {
            throw .init(from: error)
        } catch {
            throw .unknown(description: "\(error)")
        }
    }
    
    func encode<T: Encodable>(
        _ value: T,
        format: JSONEncoder.OutputFormatting = [.prettyPrinted, .sortedKeys],
        encoding: JSONEncoder.KeyEncodingStrategy = .useDefaultKeys
    ) throws(EncodingFailedError) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = format
        encoder.keyEncodingStrategy = encoding

        do {
            return try encoder.encode(value)
        } catch let error as EncodingError {
            throw .init(from: error)
        } catch {
            throw .unknown(description: "\(error)")
        }
    }
    
    public enum DecodingFailedError: LocalizedError, Equatable, Sendable {
        case dataCorrupted(context: String)
        case keyNotFound(key: String)
        case typeMismatch(expected: String, context: String)
        case valueNotFound(type: String, context: String)
        case unknown(description: String)

        init(from error: DecodingError) {
            switch error {
            case let .dataCorrupted(context):
                self = .dataCorrupted(context: context.debugDescription)
            case let .keyNotFound(key, _):
                self = .keyNotFound(key: key.stringValue)
            case let .typeMismatch(type, context):
                self = .typeMismatch(expected: String(describing: type), context: context.debugDescription)
            case let .valueNotFound(type, context):
                self = .valueNotFound(type: String(describing: type), context: context.debugDescription)
            @unknown default:
                self = .unknown(description: error.localizedDescription)
            }
        }

        var localizedDescription: String {
            switch self {
            case let .dataCorrupted(context): "data corrupted - \(context)"
            case let .keyNotFound(key): "missing key '\(key)'"
            case let .typeMismatch(expected, context): "type mismatch (expected \(expected)) - \(context)"
            case let .valueNotFound(type, context): "missing value of type \(type) - \(context)"
            case let .unknown(description): description
            }
        }
    }

    public enum EncodingFailedError: LocalizedError, Equatable, Sendable {
        case invalidValue(type: String, context: String)
        case unknown(description: String)

        init(from error: EncodingError) {
            switch error {
            case let .invalidValue(value, context):
                self = .invalidValue(type: String(describing: type(of: value)), context: context.debugDescription)
            @unknown default:
                self = .unknown(description: error.localizedDescription)
            }
        }

        var localizedDescription: String {
            switch self {
            case let .invalidValue(type, context): "invalid value of type \(type) - \(context)"
            case let .unknown(description): description
            }
        }
    }
}

extension JSONCoderClient: DependencyKey {
    public static let liveValue = JSONCoderClient()
}

extension DependencyValues {
    public var jsonCoder: JSONCoderClient {
        get { self[JSONCoderClient.self] }
        set { self[JSONCoderClient.self] = newValue }
    }
}
