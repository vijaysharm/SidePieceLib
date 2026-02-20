//
//  SSEParser.swift
//  SidePiece
//
//  Server-Sent Events parser for streaming API responses.
//

import Foundation

public struct SSEEvent: Sendable, Equatable {
    public var event: String?
    public var data: String?
    public var id: String?

    public init(event: String? = nil, data: String? = nil, id: String? = nil) {
        self.event = event
        self.data = data
        self.id = id
    }
}

public enum SSEParser {
    /// Parse Server-Sent Events from URLSession.AsyncBytes.
    /// - Parameters:
    ///   - bytes: The async byte stream to parse
    ///   - hooks: Optional hooks for intercepting SSE lines
    public static func parse(
        _ bytes: URLSession.AsyncBytes,
        hooks: StreamHooks = .default
    ) -> AsyncThrowingStream<SSEEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var lineBuffer = Data()

                var current = SSEEvent()
                var dataLines: [String] = []

                func flushEventIfNeeded() {
                    guard !dataLines.isEmpty else { return }
                    current.data = dataLines.joined(separator: "\n")
                    continuation.yield(current)
                    current = SSEEvent()
                    dataLines.removeAll(keepingCapacity: true)
                }

                do {
                    for try await byte in bytes {
                        lineBuffer.append(byte)

                        // newline
                        if byte == 0x0A {
                            // drop '\n'
                            var line = String(decoding: lineBuffer.dropLast(), as: UTF8.self)
                            lineBuffer.removeAll(keepingCapacity: true)

                            // drop '\r'
                            if line.hasSuffix("\r") { line.removeLast() }

                            // Hook: transform or observe the raw line
                            line = await hooks.didReceiveSSELine(line)

                            if line.isEmpty {
                                flushEventIfNeeded()
                                continue
                            }

                            if line.hasPrefix(":") { continue } // comment

                            if line.hasPrefix("data:") {
                                let v = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                                dataLines.append(v)
                            } else if line.hasPrefix("event:") {
                                current.event = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
                            } else if line.hasPrefix("id:") {
                                current.id = line.dropFirst(3).trimmingCharacters(in: .whitespaces)
                            } else {
                                // ignore
                            }
                        }
                    }

                    // flush any remaining
                    flushEventIfNeeded()
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
