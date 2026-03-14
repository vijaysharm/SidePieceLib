//
//  ClaudeCodeProvider.swift
//  SidePiece
//
//  AIProvider implementation wrapping the Claude CLI in headless streaming mode.
//  Uses `claude -p --output-format stream-json --verbose` for NDJSON streaming.
//

import Dependencies
import Foundation

/// Actor for storing session ID across stream() calls for `--resume` support.
public actor ClaudeCodeSessionStore {
    public var sessionId: String?

    public init(sessionId: String? = nil) {
        self.sessionId = sessionId
    }
}

// MARK: - Error

public enum ClaudeCodeError: LocalizedError, Equatable, Sendable {
    case parseError(String)
    case processFailed(ProcessStreamError)
    case noPromptFound

    public var errorDescription: String? {
        switch self {
        case .parseError(let detail):
            "Claude Code parse error: \(detail)"
        case .processFailed(let error):
            "Claude Code process error: \(error.localizedDescription)"
        case .noPromptFound:
            "No user message found to send to Claude Code"
        }
    }
}

// MARK: - Permission Mode

/// Maps to `--permission-mode`. Use `.dangerouslySkipPermissions` on `ClaudeCodeOptions`
/// for the harder `--dangerously-skip-permissions` flag instead.
public enum ClaudeCodePermissionMode: String, Sendable, Equatable {
    case `default`         = "default"
    case acceptEdits       = "acceptEdits"
    case dontAsk           = "dontAsk"
    case bypassPermissions = "bypassPermissions"
    case plan              = "plan"
    case auto              = "auto"
}

// MARK: - Builtin Tools

/// Controls which built-in Claude Code tools are available via `--tools`.
/// This is distinct from `allowedTools`/`disallowedTools`, which filter auto-approval.
public enum ClaudeCodeBuiltinTools: Sendable, Equatable {
    /// All built-in tools (CLI default). Maps to `--tools "default"`.
    case all
    /// No built-in tools. Maps to `--tools ""`.
    case none
    /// Specific subset. Maps to `--tools "Bash,Edit,Read"`.
    case only([String])
}

// MARK: - MCP Server

/// Configuration for a single MCP server passed via `--mcp-config`.
public enum ClaudeCodeMcpServer: Sendable, Equatable {
    case stdio(command: String, args: [String], env: [String: String])
    case sse(url: String, headers: [String: String])
    case http(url: String, headers: [String: String])
}

extension ClaudeCodeMcpServer {
    public static func stdio(
        _ command: String,
        args: [String] = [],
        env: [String: String] = [:]
    ) -> Self { .stdio(command: command, args: args, env: env) }

    public static func sse(_ url: String, headers: [String: String] = [:]) -> Self {
        .sse(url: url, headers: headers)
    }

    public static func http(_ url: String, headers: [String: String] = [:]) -> Self {
        .http(url: url, headers: headers)
    }
}

// MARK: - Setting Source

/// Controls which on-disk config files the CLI loads, via `--setting-sources`.
public enum ClaudeCodeSettingSource: String, Sendable, Equatable {
    case user    = "user"
    case project = "project"
    case local   = "local"
}

// MARK: - Agent Model

/// Model override for a subagent definition.
public enum ClaudeCodeAgentModel: String, Sendable, Equatable {
    case sonnet  = "sonnet"
    case opus    = "opus"
    case haiku   = "haiku"
    case inherit = "inherit"
}

// MARK: - Agent Definition

/// Defines a programmatic subagent passed via `--agents`.
public struct ClaudeCodeAgentDefinition: Sendable, Equatable {
    /// Natural language description of when to use this agent.
    public let description: String
    /// The agent's system prompt.
    public let prompt: String
    /// Allowed tool names. Empty means inherit all tools from parent.
    public let tools: [String]
    /// Tool names explicitly disallowed for this agent.
    public let disallowedTools: [String]
    /// Model override. Nil or `.inherit` uses the parent model.
    public let model: ClaudeCodeAgentModel?
    /// MCP servers available to this agent.
    public let mcpServers: [String: ClaudeCodeMcpServer]
    /// Skill names to preload into the agent context.
    public let skills: [String]
    /// Maximum agentic turns before stopping. Nil means no limit.
    public let maxTurns: Int?

    public init(
        description: String,
        prompt: String,
        tools: [String] = [],
        disallowedTools: [String] = [],
        model: ClaudeCodeAgentModel? = nil,
        mcpServers: [String: ClaudeCodeMcpServer] = [:],
        skills: [String] = [],
        maxTurns: Int? = nil
    ) {
        self.description = description
        self.prompt = prompt
        self.tools = tools
        self.disallowedTools = disallowedTools
        self.model = model
        self.mcpServers = mcpServers
        self.skills = skills
        self.maxTurns = maxTurns
    }
}

// MARK: - Options

/// All configurable options for a `ClaudeCodeProvider` session.
/// Each field corresponds directly to a CLI flag or `ProcessConfiguration` property.
public struct ClaudeCodeOptions: Sendable, Equatable {

    // MARK: Process

    /// Working directory for the CLI process. Maps to `Process.currentDirectoryURL`.
    public var cwd: URL?

    /// Additional directories to grant tool access to. Maps to `--add-dir`.
    public var additionalDirectories: [URL]

    // MARK: Permission

    /// Fine-grained permission mode. Maps to `--permission-mode`.
    /// Ignored when `dangerouslySkipPermissions` is true.
    public var permissionMode: ClaudeCodePermissionMode

    /// Bypass all permission checks. Maps to `--dangerously-skip-permissions`.
    /// Recommended only for offline sandboxes.
    public var dangerouslySkipPermissions: Bool

    /// Expose the bypass-permissions option to the user without enabling it by default.
    /// Maps to `--allow-dangerously-skip-permissions`.
    public var allowDangerouslySkipPermissions: Bool

    // MARK: Tools

    /// Restrict which built-in tools are available. Maps to `--tools`.
    /// Nil leaves the CLI default (all tools) unchanged.
    public var availableTools: ClaudeCodeBuiltinTools?

    /// Tools that are auto-approved without prompting. Maps to `--allowedTools`.
    public var allowedTools: [String]

    /// Tools that are denied entirely. Maps to `--disallowedTools`.
    public var disallowedTools: [String]

    // MARK: System Prompt

    /// Appended to Claude Code's built-in system prompt. Maps to `--append-system-prompt`.
    /// When `LLMRequestOptions.systemPrompt` is set it takes precedence via `--system-prompt`,
    /// which replaces the built-in prompt entirely; use this field to preserve it.
    public var appendSystemPrompt: String?

    // MARK: MCP

    /// MCP servers injected at session start. Serialised to inline JSON for `--mcp-config`.
    public var mcpServers: [String: ClaudeCodeMcpServer]

    /// Ignore all MCP configs except those in `mcpServers`. Maps to `--strict-mcp-config`.
    public var strictMcpConfig: Bool

    // MARK: Model

    /// Fallback model when the primary is overloaded. Maps to `--fallback-model`.
    public var fallbackModel: String?

    // MARK: Budget

    /// Maximum USD to spend on API calls per run. Maps to `--max-budget-usd`.
    public var maxBudgetUsd: Double?

    // MARK: Session

    /// Do not persist this session to disk (cannot be resumed). Maps to `--no-session-persistence`.
    public var noSessionPersistence: Bool

    /// Create a new session ID when resuming instead of reusing the original.
    /// Maps to `--fork-session`.
    public var forkSession: Bool

    /// Display name for this session shown in `/resume`. Maps to `--name`.
    public var sessionName: String?

    // MARK: Config

    /// On-disk config/CLAUDE.md sources to load. Empty disables all file-based config.
    /// Maps to `--setting-sources`.
    public var settingSources: [ClaudeCodeSettingSource]

    /// Directories to load plugins from for this session. Maps to `--plugin-dir` (repeatable).
    public var pluginDirs: [URL]

    /// Programmatic subagent definitions. Serialised to inline JSON for `--agents`.
    public var customAgents: [String: ClaudeCodeAgentDefinition]

    /// Beta feature headers (API key users only). Maps to `--betas`.
    public var betas: [String]

    public init(
        cwd: URL? = nil,
        additionalDirectories: [URL] = [],
        permissionMode: ClaudeCodePermissionMode = .default,
        dangerouslySkipPermissions: Bool = false,
        allowDangerouslySkipPermissions: Bool = false,
        availableTools: ClaudeCodeBuiltinTools? = nil,
        allowedTools: [String] = [],
        disallowedTools: [String] = [],
        appendSystemPrompt: String? = nil,
        mcpServers: [String: ClaudeCodeMcpServer] = [:],
        strictMcpConfig: Bool = false,
        fallbackModel: String? = nil,
        maxBudgetUsd: Double? = nil,
        noSessionPersistence: Bool = false,
        forkSession: Bool = false,
        sessionName: String? = nil,
        settingSources: [ClaudeCodeSettingSource] = [],
        pluginDirs: [URL] = [],
        customAgents: [String: ClaudeCodeAgentDefinition] = [:],
        betas: [String] = []
    ) {
        self.cwd = cwd
        self.additionalDirectories = additionalDirectories
        self.permissionMode = permissionMode
        self.dangerouslySkipPermissions = dangerouslySkipPermissions
        self.allowDangerouslySkipPermissions = allowDangerouslySkipPermissions
        self.availableTools = availableTools
        self.allowedTools = allowedTools
        self.disallowedTools = disallowedTools
        self.appendSystemPrompt = appendSystemPrompt
        self.mcpServers = mcpServers
        self.strictMcpConfig = strictMcpConfig
        self.fallbackModel = fallbackModel
        self.maxBudgetUsd = maxBudgetUsd
        self.noSessionPersistence = noSessionPersistence
        self.forkSession = forkSession
        self.sessionName = sessionName
        self.settingSources = settingSources
        self.pluginDirs = pluginDirs
        self.customAgents = customAgents
        self.betas = betas
    }
}

// MARK: - Provider

public struct ClaudeCodeProvider: AIProvider, Sendable {
    public let id: String = "claude-code"
    public let modelId: String
    let executablePath: String
    let sessionStore: ClaudeCodeSessionStore
    let options: ClaudeCodeOptions

    public init(
        modelId: String,
        executablePath: String = "claude",
        sessionStore: ClaudeCodeSessionStore = ClaudeCodeSessionStore(),
        options: ClaudeCodeOptions = ClaudeCodeOptions()
    ) {
        self.modelId = modelId
        self.executablePath = executablePath
        self.sessionStore = sessionStore
        self.options = options
    }

    public func stream(
        items: [ConversationItem],
        options requestOptions: LLMRequestOptions
    ) -> AsyncThrowingStream<LLMStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let prompt = extractPrompt(from: items) else {
                        let error = ClaudeCodeError.noPromptFound
                        continuation.yield(.finished(usage: nil, finishReason: .error(
                            LLMError(code: "NO_PROMPT", message: error.localizedDescription)
                        )))
                        continuation.finish()
                        return
                    }

                    var args = ["-p", prompt, "--output-format", "stream-json", "--verbose"]

                    // Session resumption
                    if let sessionId = await sessionStore.sessionId {
                        args.append(contentsOf: ["--resume", sessionId])
                        if options.forkSession {
                            args.append("--fork-session")
                        }
                    }

                    // Model
                    args.append(contentsOf: ["--model", modelId])
                    if let fallback = options.fallbackModel {
                        args.append(contentsOf: ["--fallback-model", fallback])
                    }

                    // Permission
                    if options.dangerouslySkipPermissions {
                        args.append("--dangerously-skip-permissions")
                    } else if options.allowDangerouslySkipPermissions {
                        args.append("--allow-dangerously-skip-permissions")
                    } else if options.permissionMode != .default {
                        args.append(contentsOf: ["--permission-mode", options.permissionMode.rawValue])
                    }

                    // System prompt — --system-prompt replaces the built-in prompt entirely;
                    // --append-system-prompt preserves it and appends.
                    if let systemPrompt = requestOptions.systemPrompt {
                        args.append(contentsOf: ["--system-prompt", systemPrompt])
                    } else if let append = options.appendSystemPrompt {
                        args.append(contentsOf: ["--append-system-prompt", append])
                    }

                    // Tools
                    if let available = options.availableTools {
                        args.append(contentsOf: ["--tools", available.cliValue])
                    }
                    if !options.allowedTools.isEmpty {
                        args.append(contentsOf: ["--allowedTools", options.allowedTools.joined(separator: ",")])
                    }
                    if !options.disallowedTools.isEmpty {
                        args.append(contentsOf: ["--disallowedTools", options.disallowedTools.joined(separator: ",")])
                    }

                    // Directories
                    if !options.additionalDirectories.isEmpty {
                        args.append("--add-dir")
                        args.append(contentsOf: options.additionalDirectories.map(\.path))
                    }

                    // MCP
                    if !options.mcpServers.isEmpty, let json = mcpConfigJSON(options.mcpServers) {
                        args.append(contentsOf: ["--mcp-config", json])
                    }
                    if options.strictMcpConfig {
                        args.append("--strict-mcp-config")
                    }

                    // Budget
                    if let budget = options.maxBudgetUsd {
                        args.append(contentsOf: ["--max-budget-usd", String(budget)])
                    }

                    // Session flags
                    if options.noSessionPersistence {
                        args.append("--no-session-persistence")
                    }
                    if let name = options.sessionName {
                        args.append(contentsOf: ["--name", name])
                    }

                    // Config sources
                    if !options.settingSources.isEmpty {
                        let sources = options.settingSources.map(\.rawValue).joined(separator: ",")
                        args.append(contentsOf: ["--setting-sources", sources])
                    }

                    // Plugins
                    for dir in options.pluginDirs {
                        args.append(contentsOf: ["--plugin-dir", dir.path])
                    }

                    // Custom agents
                    if !options.customAgents.isEmpty, let json = agentsJSON(options.customAgents) {
                        args.append(contentsOf: ["--agents", json])
                    }

                    // Betas
                    if !options.betas.isEmpty {
                        args.append(contentsOf: ["--betas"] + options.betas)
                    }

                    // Reasoning effort → --effort
                    if let effort = requestOptions.reasoningEffort {
                        switch effort {
                        case .none:   break
                        case .low:    args.append(contentsOf: ["--effort", "low"])
                        case .medium: args.append(contentsOf: ["--effort", "medium"])
                        case .high:   args.append(contentsOf: ["--effort", "high"])
                        }
                    }

                    let configuration = ProcessConfiguration(
                        executablePath: executablePath,
                        arguments: args,
                        workingDirectory: options.cwd
                    )

                    @Dependency(\.processStreamClient) var processClient
                    let handle: ProcessHandle
                    do {
                        handle = try await processClient.spawn(configuration)
                    } catch let error as ProcessStreamError {
                        let llmError = LLMError(
                            code: "PROCESS_SPAWN_FAILED",
                            message: error.localizedDescription
                        )
                        continuation.yield(.finished(usage: nil, finishReason: .error(llmError)))
                        continuation.finish()
                        return
                    }

                    // Close stdin immediately — claude -p gets the prompt via CLI args
                    // and reads stdin until EOF, so an open pipe would hang forever.
                    await handle.closeStdin()

                    // Drain stderr in background so the pipe doesn't block
                    _ = Task {
                        for try await line in handle.stderr {
                            print("[ClaudeCode] stderr: \(String(line.prefix(200)))")
                        }
                    }

                    let events = NDJSONParser.parse(handle.stdout)
                    var usage: TokenUsage?
                    var eventCount = 0

                    for try await json in events {
                        guard case let .object(obj) = json else { continue }
                        let type = obj["type"]?.stringValue ?? ""
                        eventCount += 1
                        if eventCount <= 5 { print("[ClaudeCode] event #\(eventCount): type=\(type)") }

                        switch type {
                        // Claude Code CLI emits a "system" init event with session metadata
                        case "system":
                            if let sessionId = obj["session_id"]?.stringValue {
                                await sessionStore.update(sessionId: sessionId)
                            }

                        // "assistant" events contain the full message with content blocks
                        case "assistant":
                            if let msg = obj["message"]?.objectValue {
                                if let u = msg["usage"]?.objectValue {
                                    let input = u["input_tokens"]?.intValue ?? 0
                                    let output = u["output_tokens"]?.intValue ?? 0
                                    let cacheCreation = u["cache_creation_input_tokens"]?.intValue ?? 0
                                    let cacheRead = u["cache_read_input_tokens"]?.intValue ?? 0
                                    usage = TokenUsage(
                                        promptTokens: input + cacheCreation + cacheRead,
                                        completionTokens: output
                                    )
                                }

                                if let content = msg["content"]?.arrayValue {
                                    for block in content {
                                        guard let blockObj = block.objectValue,
                                              let blockType = blockObj["type"]?.stringValue else { continue }

                                        switch blockType {
                                        case "text":
                                            let text = blockObj["text"]?.stringValue ?? ""
                                            if !text.isEmpty {
                                                continuation.yield(.textDelta(text))
                                            }

                                        case "thinking":
                                            let thinking = blockObj["thinking"]?.stringValue ?? ""
                                            if !thinking.isEmpty {
                                                continuation.yield(.reasoningDelta(thinking))
                                            }

                                        case "tool_use":
                                            let toolId = blockObj["id"]?.stringValue ?? "call_\(UUID().uuidString)"
                                            let name = blockObj["name"]?.stringValue ?? "tool"
                                            let input = blockObj["input"]
                                            let argStr: String
                                            if let input,
                                               let data = try? JSONEncoder().encode(input) {
                                                argStr = String(data: data, encoding: .utf8) ?? "{}"
                                            } else {
                                                argStr = "{}"
                                            }
                                            continuation.yield(.toolCallStart(id: toolId, name: name))
                                            continuation.yield(.toolCallDelta(id: toolId, args: argStr))
                                            continuation.yield(.toolCallEnd(id: toolId, name: name, arguments: argStr))

                                        default:
                                            break
                                        }
                                    }
                                }
                            }

                        // "result" is the final event with session and usage info
                        case "result":
                            if let sessionId = obj["session_id"]?.stringValue {
                                await sessionStore.update(sessionId: sessionId)
                            }
                            if let u = obj["usage"]?.objectValue {
                                let input = u["input_tokens"]?.intValue ?? 0
                                let output = u["output_tokens"]?.intValue ?? 0
                                usage = TokenUsage(promptTokens: input, completionTokens: output)
                            }
                            let isError = obj["is_error"]?.boolValue ?? false
                            if isError {
                                let msg = obj["result"]?.stringValue ?? "Claude Code error"
                                let error = LLMError(code: "CLAUDE_CODE_ERROR", message: msg)
                                continuation.yield(.finished(usage: usage, finishReason: .error(error)))
                            } else {
                                continuation.yield(.finished(usage: usage, finishReason: .stop))
                            }

                        case "error":
                            let errorObj = obj["error"]?.objectValue
                            let code = errorObj?["type"]?.stringValue ?? "CLAUDE_CODE_ERROR"
                            let msg = errorObj?["message"]?.stringValue ?? obj["message"]?.stringValue ?? "Claude Code error"
                            let error = LLMError(code: code, message: msg)
                            continuation.yield(.finished(usage: usage, finishReason: .error(error)))

                        default:
                            // Ignore rate_limit_event, user (tool activity), and other unknown types
                            break
                        }
                    }

                    continuation.finish()
                } catch {
                    let llmError: LLMError
                    if let e = error as? LLMError {
                        llmError = e
                    } else {
                        llmError = LLMError(
                            code: "STREAM_FAILED",
                            message: "Streaming failed",
                            underlying: String(describing: error)
                        )
                    }
                    continuation.yield(.finished(usage: nil, finishReason: .error(llmError)))
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    // MARK: - Helpers

    private func extractPrompt(from items: [ConversationItem]) -> String? {
        for item in items.reversed() {
            if case let .message(role, content) = item, role == .user {
                return content.compactMap { part in
                    if case let .text(text) = part { return text }
                    return nil
                }.joined(separator: "\n")
            }
        }
        return nil
    }
}

// MARK: - Session Store Extension

extension ClaudeCodeSessionStore {
    func update(sessionId: String) {
        self.sessionId = sessionId
    }
}

// MARK: - ClaudeCodeBuiltinTools CLI value

private extension ClaudeCodeBuiltinTools {
    var cliValue: String {
        switch self {
        case .all:           return "default"
        case .none:          return ""
        case .only(let ts):  return ts.joined(separator: ",")
        }
    }
}

// MARK: - JSON Serialisation Helpers

/// Serialises `[name: ClaudeCodeMcpServer]` to the inline JSON string expected by `--mcp-config`.
private func mcpConfigJSON(_ servers: [String: ClaudeCodeMcpServer]) -> String? {
    var dict: [String: Any] = [:]
    for (name, server) in servers {
        switch server {
        case .stdio(let command, let args, let env):
            var entry: [String: Any] = ["type": "stdio", "command": command, "args": args]
            if !env.isEmpty { entry["env"] = env }
            dict[name] = entry
        case .sse(let url, let headers):
            var entry: [String: Any] = ["type": "sse", "url": url]
            if !headers.isEmpty { entry["headers"] = headers }
            dict[name] = entry
        case .http(let url, let headers):
            var entry: [String: Any] = ["type": "http", "url": url]
            if !headers.isEmpty { entry["headers"] = headers }
            dict[name] = entry
        }
    }
    let config: [String: Any] = ["mcpServers": dict]
    guard let data = try? JSONSerialization.data(withJSONObject: config, options: .sortedKeys),
          let json = String(data: data, encoding: .utf8) else { return nil }
    return json
}

/// Serialises `[name: ClaudeCodeAgentDefinition]` to the inline JSON string expected by `--agents`.
private func agentsJSON(_ agents: [String: ClaudeCodeAgentDefinition]) -> String? {
    var dict: [String: Any] = [:]
    for (name, agent) in agents {
        var entry: [String: Any] = [
            "description": agent.description,
            "prompt": agent.prompt,
        ]
        if !agent.tools.isEmpty          { entry["tools"] = agent.tools }
        if !agent.disallowedTools.isEmpty { entry["disallowedTools"] = agent.disallowedTools }
        if let model = agent.model       { entry["model"] = model.rawValue }
        if !agent.skills.isEmpty         { entry["skills"] = agent.skills }
        if let maxTurns = agent.maxTurns { entry["maxTurns"] = maxTurns }
        if !agent.mcpServers.isEmpty {
            // Agents expect mcpServers as a dict matching the top-level MCP config format.
            var serverDict: [String: Any] = [:]
            for (sName, server) in agent.mcpServers {
                switch server {
                case .stdio(let command, let args, let env):
                    var s: [String: Any] = ["type": "stdio", "command": command, "args": args]
                    if !env.isEmpty { s["env"] = env }
                    serverDict[sName] = s
                case .sse(let url, let headers):
                    var s: [String: Any] = ["type": "sse", "url": url]
                    if !headers.isEmpty { s["headers"] = headers }
                    serverDict[sName] = s
                case .http(let url, let headers):
                    var s: [String: Any] = ["type": "http", "url": url]
                    if !headers.isEmpty { s["headers"] = headers }
                    serverDict[sName] = s
                }
            }
            entry["mcpServers"] = serverDict
        }
        dict[name] = entry
    }
    guard let data = try? JSONSerialization.data(withJSONObject: dict, options: .sortedKeys),
          let json = String(data: data, encoding: .utf8) else { return nil }
    return json
}
