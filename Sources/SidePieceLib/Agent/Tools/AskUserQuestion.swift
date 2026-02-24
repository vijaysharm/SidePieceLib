//
//  AskUserQuestion.swift
//  SidePiece
//
//  Tool that presents questions with selectable options to the user.
//  Uses the unified `.questionnaire` interaction type — the tool's arguments
//  define the questions, and the ToolCallBlockView renders them as an
//  interactive form. The user's answers flow back through the tool result.
//

import Foundation

// MARK: - Tool

public struct AskUserQuestionTool: TypedTool {
    public let name = "ask_user_question"
    public let description =
        "Present questions with selectable options to the user. " +
        "Use this to clarify ambiguous requirements, gather user preferences, " +
        "let users choose between implementation approaches, or present " +
        "side-by-side previews for comparison. Supports single-select and " +
        "multi-select questions, optional markdown previews, and 1 to 4 " +
        "questions per call."
    public let interaction: ToolInteraction = .questionnaire

    // MARK: - Input

    public struct Input: ToolInput {
        /// The questions to present (1-4).
        public let questions: [QuestionItem]

        /// Optional pre-filled answers keyed by question text.
        public let answers: [String: String]?

        /// Optional per-question annotations (e.g. notes on previews).
        public let annotations: [String: AnnotationValue]?

        /// Optional tracking metadata.
        public let metadata: MetadataValue?

        public struct AnnotationValue: Decodable, Sendable {
            public let markdown: String?
            public let notes: String?
        }

        public struct MetadataValue: Decodable, Sendable {
            public let source: String?
        }

        public static var schema: JSONValue {
            .objectSchema(
                properties: [
                    "questions": .arrayProperty(
                        description: "Array of questions to present to the user (1-4)",
                        items: .objectSchema(
                            properties: [
                                "question": .stringProperty(
                                    description: "The complete question to ask the user"
                                ),
                                "header": .stringProperty(
                                    description: "Very short label displayed as a chip/tag (max 12 chars)"
                                ),
                                "options": .arrayProperty(
                                    description: "The available choices (2-4 options)",
                                    items: .objectSchema(
                                        properties: [
                                            "label": .stringProperty(
                                                description: "Display text for this option (1-5 words)"
                                            ),
                                            "description": .stringProperty(
                                                description: "Explanation of what this option means"
                                            ),
                                            "markdown": .stringProperty(
                                                description: "Optional preview content shown when this option is focused"
                                            ),
                                        ],
                                        required: ["label", "description"]
                                    )
                                ),
                                "multi_select": .boolProperty(
                                    description: "Set to true to allow multiple selections"
                                ),
                            ],
                            required: ["question", "header", "options", "multi_select"]
                        )
                    ),
                    "answers": .objectProperty(
                        description: "Optional pre-filled answers keyed by question text",
                        properties: [:]
                    ),
                    "annotations": .objectProperty(
                        description: "Optional per-question annotations",
                        properties: [:]
                    ),
                    "metadata": .objectProperty(
                        description: "Optional tracking metadata",
                        properties: [
                            "source": .stringProperty(description: "Identifier for the source of this question"),
                        ]
                    ),
                ],
                required: ["questions"]
            )
        }
    }

    // MARK: - Output

    public struct Output: ToolOutput {
        /// The user's answers keyed by question text.
        public let answers: [String: String]

        public var toolResultString: String {
            get throws {
                let result: JSONValue = .object(
                    Dictionary(uniqueKeysWithValues: answers.map { key, value in
                        (key, JSONValue.string(value))
                    })
                )
                return try result.toJSONString()
            }
        }
    }

    // MARK: - Execute

    /// The user's answers arrive via `userResponse` as a JSON string from the
    /// questionnaire UI. This method decodes them and returns the result.
    public func execute(_ input: Input, userResponse: String?, projectURL: URL) async throws -> Output {
        guard let response = userResponse,
              let data = response.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let answers = parsed["answers"] as? [String: String]
        else {
            throw ToolExecutionError.unknown("No user response received for ask_user_question")
        }

        return Output(answers: answers)
    }

    /// Not used directly — the `userResponse` variant handles execution.
    public func execute(_ input: Input, projectURL: URL) async throws -> Output {
        throw ToolExecutionError.unknown("ask_user_question requires user interaction")
    }
}

// MARK: - Tool Extension

extension Tool {
    public static let askUserQuestion = Tool(AskUserQuestionTool())
}
