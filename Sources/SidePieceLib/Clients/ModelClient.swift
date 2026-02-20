//
//  ModelClient.swift
//  SidePiece
//

import Dependencies
import DependenciesMacros
import Foundation

@DependencyClient
public struct ModelClient: Sendable {
    var models: @Sendable () async throws -> Models
}

private enum ModelCache {
    static var cacheURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let bundleId = Bundle.main.bundleIdentifier ?? ""
        return appSupport
            .appendingPathComponent(bundleId)
            .appendingPathComponent("Cache")
            .appendingPathComponent("models.dev.api.json")
    }

    static func fetch(timeout: TimeInterval = 5) async throws -> Data {
        let url = URL(string: "https://models.dev/api.json")!
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        let session = URLSession(configuration: config)
        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    static func save(_ data: Data) throws {
        let dir = cacheURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try data.write(to: cacheURL, options: .atomic)
    }

    static func loadCached() -> Data? {
        FileManager.default.contents(atPath: cacheURL.path)
    }
}

extension ModelClient {
    public init (
        transformer: @Sendable @escaping (ModelRegistry.LLMRegistry) async throws -> Models
    ) {
        self.init(
            models: {
                @Dependency(\.jsonCoder) var coder

                // Try fetching fresh data from the network
                if let data = try? await ModelCache.fetch(),
                   let registry = try? coder.decode(ModelRegistry.LLMRegistry.self, from: data) {
                    try? ModelCache.save(data)
                    return try await transformer(registry)
                }

                // Try reading from the local cache
                if let data = ModelCache.loadCached(),
                   let registry = try? coder.decode(ModelRegistry.LLMRegistry.self, from: data) {
                    return try await transformer(registry)
                }

                return try await transformer(ModelRegistry.LLMRegistry(providers: [:]))
            }
        )
    }
}

extension ModelClient: DependencyKey {
    public static let liveValue = ModelClient(
        models: {
            fatalError("No Models to provide.")
        }
    )
}

extension DependencyValues {
    public var modelClient: ModelClient {
        get { self[ModelClient.self] }
        set { self[ModelClient.self] = newValue }
    }
}
