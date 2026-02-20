//
//  ReplayProvider.swift
//  SidePiece
//
//  Provider that replays recorded sessions for testing and debugging.
//

import Foundation

/// Provider that replays a recorded session instead of making real API calls.
/// Useful for testing, debugging, and reproducing issues.
public struct ReplayProvider: AIProvider, Sendable {
    public let id: String = "replay"
    public let modelId: String

    private let session: RecordedSession
    private let playbackSpeed: Double

    /// Initialize with a recorded session
    public init(session: RecordedSession, playbackSpeed: Double = 1.0) {
        self.session = session
        self.modelId = "replay-\(session.id.uuidString.prefix(8))"
        self.playbackSpeed = playbackSpeed
    }

    /// Initialize from a recorded session file
    public init(fileURL: URL, playbackSpeed: Double = 1.0) throws {
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.session = try decoder.decode(RecordedSession.self, from: data)
        self.modelId = "replay-\(session.id.uuidString.prefix(8))"
        self.playbackSpeed = playbackSpeed
    }

    public func stream(
        items: [ConversationItem],
        options: LLMRequestOptions
    ) -> AsyncThrowingStream<LLMStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    // Replay SSE lines with timing
                    var previousTimestamp: Date?

                    for line in session.response.lines {
                        // Simulate timing between lines
                        if let prev = previousTimestamp, playbackSpeed > 0 {
                            let delay = line.timestamp.timeIntervalSince(prev) / playbackSpeed
                            if delay > 0 && delay < 10 { // Cap at 10 seconds
                                try await Task.sleep(for: .seconds(delay))
                            }
                        }
                        previousTimestamp = line.timestamp

                        // Parse the SSE line and convert to LLMStreamEvent
                        if let event = parseSSELine(line.content) {
                            continuation.yield(event)
                        }
                    }

                    // Handle completion or error
                    if let error = session.response.error {
                        let llmError = LLMError(
                            code: "REPLAY_ERROR",
                            message: error.message
                        )
                        continuation.yield(.finished(usage: nil, finishReason: .error(llmError)))
                        continuation.finish(throwing: llmError)
                    } else {
                        continuation.yield(.finished(usage: nil, finishReason: .stop))
                        continuation.finish()
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    /// Parse an SSE line into an LLMStreamEvent
    /// This needs to handle the provider-specific format that was recorded
    private func parseSSELine(_ line: String) -> LLMStreamEvent? {
        // Skip empty lines and comments
        if line.isEmpty || line.hasPrefix(":") {
            return nil
        }

        // Extract data from "data: {...}" lines
        guard line.hasPrefix("data:") else { return nil }

        let jsonString = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)

        // Handle [DONE] marker (OpenAI)
        if jsonString == "[DONE]" {
            return nil // Completion handled separately
        }

        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONDecoder().decode(JSONValue.self, from: data),
              case let .object(obj) = json else {
            return nil
        }

        // Detect provider format and parse accordingly
        return parseProviderEvent(obj)
    }

    private func parseProviderEvent(_ obj: [String: JSONValue]) -> LLMStreamEvent? {
        let type = obj["type"]?.stringValue ?? ""

        // Anthropic format
        if type.contains("content_block_delta") || type.contains("message") {
            return parseAnthropicEvent(type: type, obj: obj)
        }

        // OpenAI format
        if type.contains("response.") {
            return parseOpenAIEvent(type: type, obj: obj)
        }

        return nil
    }

    private func parseAnthropicEvent(type: String, obj: [String: JSONValue]) -> LLMStreamEvent? {
        switch type {
        case "content_block_delta":
            if let delta = obj["delta"]?.objectValue {
                let dType = delta["type"]?.stringValue ?? ""
                if dType == "text_delta" {
                    let text = delta["text"]?.stringValue ?? ""
                    return text.isEmpty ? nil : .textDelta(text)
                } else if dType == "input_json_delta" {
                    // Tool call delta - would need context to handle properly
                    return nil
                } else if dType == "thinking_delta" {
                    let text = delta["thinking"]?.stringValue ?? ""
                    return text.isEmpty ? nil : .reasoningDelta(text)
                }
            }
        case "message_stop":
            return nil // Handled at end
        default:
            break
        }
        return nil
    }

    private func parseOpenAIEvent(type: String, obj: [String: JSONValue]) -> LLMStreamEvent? {
        switch type {
        case "response.output_text.delta", "response.content_part.delta":
            let delta = obj["delta"]?.stringValue ?? ""
            return delta.isEmpty ? nil : .textDelta(delta)
        case "response.reasoning_summary_text.delta":
            let delta = obj["delta"]?.stringValue ?? ""
            return delta.isEmpty ? nil : .reasoningDelta(delta)
        default:
            break
        }
        return nil
    }
}

// MARK: - Convenience Extensions

extension ReplayProvider {
    /// Create a replay provider from the most recent recording in a directory
    public static func fromLatestRecording(
        in directory: URL,
        playbackSpeed: Double = 1.0
    ) throws -> ReplayProvider {
        let files = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension == "json" }
        .sorted { url1, url2 in
            let date1 = (try? url1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            let date2 = (try? url2.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            return date1 > date2
        }

        guard let latest = files.first else {
            throw LLMError(code: "NO_RECORDINGS", message: "No recordings found in directory")
        }

        return try ReplayProvider(fileURL: latest, playbackSpeed: playbackSpeed)
    }
}
