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
                    var lineCount = 0
                    for try await line in lines {
                        lineCount += 1
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        if lineCount <= 3 {
                            let safe = trimmed.prefix(150).map { $0.isASCII && !$0.isNewline ? $0 : "?" }.map(String.init).joined()
                            print("[NDJSONParser] line \(lineCount) (\(trimmed.count) chars): \(safe)")
                        }
                        guard !trimmed.isEmpty, trimmed.hasPrefix("{") else { continue }

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
