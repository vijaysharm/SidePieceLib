//
//  NDJSONParser.swift
//  SidePiece
//
//  Newline-delimited JSON parser for subprocess stdout streams.
//

import Foundation

public enum NDJSONParser {
    /// Parse newline-delimited JSON from an async stream of lines.
    /// Each non-empty line is decoded as a `JSONValue`.
    public static func parse(
        _ lines: AsyncThrowingStream<String, Error>
    ) -> AsyncThrowingStream<JSONValue, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let decoder = JSONDecoder()
                    for try await line in lines {
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { continue }

                        let json = try decoder.decode(JSONValue.self, from: Data(trimmed.utf8))
                        continuation.yield(json)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }
}
