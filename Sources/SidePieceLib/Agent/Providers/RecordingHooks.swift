//
//  RecordingHooks.swift
//  SidePiece
//
//  Recording hooks for capturing streaming sessions to disk.
//

import Foundation

/// Recorded session data that can be saved to disk and replayed
public struct RecordedSession: Codable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let request: RecordedRequest
    public var response: RecordedResponse

    public struct RecordedRequest: Codable, Sendable {
        public let url: URL
        public let method: String
        public let headers: [String: String]
        public let body: Data?
    }

    public struct RecordedResponse: Codable, Sendable {
        public var statusCode: Int?
        public var headers: [String: String]?
        public var lines: [TimestampedLine]
        public var error: RecordedError?
        public var completedAt: Date?

        public init(
            statusCode: Int? = nil,
            headers: [String: String]? = nil,
            lines: [TimestampedLine] = [],
            error: RecordedError? = nil,
            completedAt: Date? = nil
        ) {
            self.statusCode = statusCode
            self.headers = headers
            self.lines = lines
            self.error = error
            self.completedAt = completedAt
        }
    }

    public struct TimestampedLine: Codable, Sendable {
        public let content: String
        public let timestamp: Date
    }

    public struct RecordedError: Codable, Sendable {
        public let message: String
        public let timestamp: Date
    }

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        request: RecordedRequest,
        response: RecordedResponse = RecordedResponse()
    ) {
        self.id = id
        self.timestamp = timestamp
        self.request = request
        self.response = response
    }
}

/// Actor that accumulates session data and writes to disk
public actor SessionRecorder {
    private var session: RecordedSession
    private let outputURL: URL

    public init(outputURL: URL) {
        self.outputURL = outputURL
        self.session = RecordedSession(
            request: RecordedSession.RecordedRequest(
                url: URL(string: "https://placeholder")!,
                method: "POST",
                headers: [:],
                body: nil
            )
        )
    }

    public func recordRequest(_ request: URLRequest) {
        session = RecordedSession(
            id: session.id,
            timestamp: session.timestamp,
            request: RecordedSession.RecordedRequest(
                url: request.url!,
                method: request.httpMethod ?? "POST",
                headers: sanitizeHeaders(request.allHTTPHeaderFields ?? [:]),
                body: request.httpBody
            ),
            response: session.response
        )
    }

    public func recordResponse(_ response: HTTPURLResponse) {
        session.response.statusCode = response.statusCode
        session.response.headers = response.allHeaderFields.reduce(into: [:]) { result, pair in
            if let key = pair.key as? String, let value = pair.value as? String {
                result[key] = value
            }
        }
    }

    public func recordLine(_ line: String) {
        session.response.lines.append(
            RecordedSession.TimestampedLine(content: line, timestamp: Date())
        )
    }

    public func recordError(_ error: Error) {
        session.response.error = RecordedSession.RecordedError(
            message: String(describing: error),
            timestamp: Date()
        )
    }

    public func recordCompletion() {
        session.response.completedAt = Date()
    }

    /// Write the session to disk
    public func save() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(session)
        try data.write(to: outputURL, options: .atomic)
    }

    /// Get the recorded session (for inspection)
    public func getSession() -> RecordedSession {
        session
    }

    private func sanitizeHeaders(_ headers: [String: String]) -> [String: String] {
        var result = headers
        for key in ["x-api-key", "authorization", "Authorization"] {
            if result[key] != nil {
                result[key] = "[REDACTED]"
            }
        }
        return result
    }
}

/// Factory to create recording hooks that write to a file
public enum RecordingHooks {
    /// Create hooks that record the session to the specified file
    public static func recording(to url: URL) -> (hooks: StreamHooks, recorder: SessionRecorder) {
        let recorder = SessionRecorder(outputURL: url)

        let hooks = StreamHooks(
            willSendRequest: { request in
                await recorder.recordRequest(request)
                return request
            },
            didReceiveResponse: { response in
                await recorder.recordResponse(response)
            },
            didReceiveSSELine: { line in
                await recorder.recordLine(line)
                return line
            },
            didComplete: {
                await recorder.recordCompletion()
                try? await recorder.save()
            },
            didFail: { error in
                await recorder.recordError(error)
                try? await recorder.save()
            }
        )

        return (hooks, recorder)
    }
}
