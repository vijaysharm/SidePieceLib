# SidePieceLib

Swift Package (macOS 15+, Swift 6.1+, strict concurrency) providing the core library for the SidePiece AI chat application. Built entirely on TCA (ComposableArchitecture v1.23.2+) with Textual for rich text rendering.

## Build

```bash
swift build
```

No test target exists. Verify changes compile with `swift build`.

## Architecture

TCA-first: every feature is a `@Reducer` with `@ObservableState`. Each feature owns its own store — no shared/generic/reusable stores, no callback patterns.

### Reducer hierarchy

```
RootFeature
├── ProjectFeature
│   └── ConversationFeature (IdentifiedArray, forEach)
│       └── MessagesFeature
│           ├── MessageTitleFeature
│           └── MessageItemFeature (IdentifiedArray, forEach)
│               └── MessageItemResponseFeature
├── SettingsFeature
├── ShortcutFeature
└── Destination (enum: ImageOverlay, ModelSelection, DeleteConfirmation, DirectoryModal)
```

### Directory layout

```
Sources/SidePieceLib/
├── Agent/           # LLM types, providers (OpenAI/Anthropic), tool system
│   ├── Providers/   # AIProvider implementations, JSONValue helpers
│   └── Tools/       # TypedTool implementations (ReadFile, WriteFile, etc.)
├── Clients/         # @DependencyClient wrappers (ModelClient, KeychainClient, etc.)
├── Conversation/    # Message features, persistence, context input
├── Editor/          # NSTextView/NSScrollView wrappers (AppKit interop)
├── Extensions/      # Type+Extension.swift files
├── Keyboard/        # Keyboard shortcut monitoring
├── Project/         # Project management, conversation list
├── RecentProjectsSelection/
├── Settings/        # Settings UI and storage
├── Resources/       # Privacy manifest
└── Utilities/       # StorageKey, JSON helpers
```

## Design philosophy

### Value types everywhere

Zero classes in the codebase except where AppKit demands inheritance (`NSTextView`, `NSScrollView`, `NSTextAttachment`). Use structs and enums for data. Use actors only for isolated mutable state (they are reference types). Never introduce a class unless subclassing a framework type that requires it.

### Enums over protocols

For **variant types** (a value that can be one of several cases), default to enums. The codebase uses enums where many projects would reach for protocols:

| Enum | What it replaces |
|---|---|
| `ContentPart` | A "ContentPartProtocol" with Text/Image/File conformers |
| `ConversationItem` | A "ConversationItemProtocol" with message/toolCall/toolResult types |
| `LLMStreamEvent` | An "EventProtocol" with separate event type conformers |
| `FinishReason` | A "FinishReasonProtocol" or class hierarchy |
| `ReasoningEffort` | A configuration protocol |
| `MediaTypeDetector` | A caseless enum used as a namespace (not a utility class) |

Use protocols for open polymorphism, associated-type generics, and type constraints on generic APIs:

| Protocol | Justification |
|---|---|
| `AIProvider` | Open set of LLM provider implementations (OpenAI, Anthropic, etc.) — cannot enumerate at compile time |
| `TypedTool` / `ToolInput` / `ToolOutput` | Associated-type generics with type erasure — the tool system needs to erase concrete types into a uniform `Tool` |
| `StorageKeyIdentifiable`, `InMemoryKey`, `UserPrefernceKey`, `KeychainKey`, `SettingIdentifiable`, `ModelIdentifiable` | Marker/constraint protocols — used as generic type constraints to restrict which types can be used with storage and settings APIs |

**Rule:** For variant types, prefer enums. If you want to add a protocol, explain the use case — open polymorphism, associated types, or generic constraints are all valid reasons.

### Extensions for dot-syntax

Extend standard library and framework types with static properties/methods for dot-syntax call sites. Name files `Type+Extension.swift` and place in `Extensions/` (or co-locate when tightly coupled to a feature).

```swift
// KeyboardShortcut dot-syntax (Root.swift)
extension KeyboardShortcut {
    public static let nextAgent = KeyboardShortcut(key: .tab, modifiers: [.shift])
    public static let closeOpenDialogs = KeyboardShortcut(key: .escape)
}

// Tool dot-syntax (ReadFile.swift)
extension Tool {
    public static let readFile = Tool(ReadFileTool())
}
```

### Swift concurrency

- `async/await` for all asynchronous work
- `AsyncThrowingStream` for streaming (SSE parsing, LLM events)
- `actor` only for stateful concurrent resources (`HTTPStreamClient`, `AssetLoader`) — not as a default
- All types must be `Sendable` (strict concurrency is enabled)
- `@unchecked Sendable` is acceptable for type-erased wrappers (e.g., structs holding `AnyHashable`) where the developer can guarantee the erased value was `Sendable` before erasure. See `StorageKeyIdentifier`, `ModelIdentifier` for examples. Do not use it to silence compiler warnings on types with genuinely non-sendable state.
- `@MainActor` for code that must run on the main thread — SwiftUI views are implicitly `@MainActor`
- Use `throws(SpecificError)` (typed throwing, Swift 6+) to preserve error type information at call sites. See `JSONCoderClient`, `FileStorageClient`, `Bundle+Extension` for examples.
- This project uses Swift concurrency exclusively — no Combine, no `@Published`, no `ObservableObject`. This is a project convention, not a statement that Combine is deprecated.

### Error handling

- **Typed errors, not raw `Error`:** Define domain-specific error enums/structs. Never catch a raw `Error` and stringify it — preserve type information.
- **All errors must be `Sendable` and `Equatable`:** `Sendable` is required by Swift's strict concurrency. `Equatable` is required by TCA (actions must be `Equatable`). When system errors resist `Equatable` conformance, transform them into an equatable domain error (see error transformation below). Pattern: `enum FooError: LocalizedError, Equatable, Sendable { ... }`
- **Typed throwing:** Use `throws(SpecificError)` syntax to make error types visible at call sites. Reference: `JSONCoderClient.decode(_:from:decoding:) throws(DecodingFailedError)`
- **Error transformation:** Convert system errors (`NSError`, `DecodingError`) into semantic cases via `init(from error:)`. Reference: `FileStorageError.FileSystemReason`, `DecodingFailedError`
- **Error composition:** Wrap lower-level typed errors as associated values. Reference: `BundleError.jsonDecodingFailed(DecodingFailedError)`, `FileStorageError.manifestDecodingFailed(reason:)`
- **Surface through TCA:** Errors reach the UI through delegate actions or `Result` types in internal actions, ultimately rendered by `ErrorBlockFeature`. Reference: `MessageItemResponseFeature.InternalAction.toolCallComplete(_, Result<String, ToolExecutionError>)`
- **Anti-pattern:** `catch { await send(.failed("\(error)")) }` — stringifying errors loses type information. Catch specific typed errors or transform to a domain error type.

## TCA conventions

### Action structure

```swift
public enum Action: Equatable {
    // Public actions (sent from views or parent reducers)
    case onAppear
    case someChildFeature(ChildFeature.Action)

    // Internal actions (implementation details)
    case `internal`(InternalAction)

    // Delegate actions (communicate up to parent)
    case delegate(DelegateAction)

    @CasePathable
    public enum InternalAction: Equatable { ... }

    @CasePathable
    public enum DelegateAction: Equatable { ... }
}
```

### Navigation

Use `@Presents` with `@Reducer enum Destination`:

```swift
@Reducer
public enum Destination {
    case featureA(FeatureA)
    case featureB(FeatureB)
}

// In State:
@Presents var destination: Destination.State?

// In body:
.ifLet(\.$destination, action: \.destination)
```

### Collections

Use `IdentifiedArrayOf<ChildFeature.State>` (never plain arrays) with `.forEach`. State types used in `IdentifiedArrayOf` must conform to `Identifiable`. Prefer making state types `Identifiable` by default when they represent discrete items.

```swift
// State
var messageItems: IdentifiedArrayOf<MessageItemFeature.State> = []

// Body
.forEach(\.messageItems, action: \.messageItems) {
    MessageItemFeature()
}
```

### Dependencies

Use the `@DependencyClient` macro pattern:

```swift
@DependencyClient
public struct ModelClient: Sendable {
    var models: @Sendable () async throws -> Models
}

extension ModelClient: DependencyKey {
    public static let liveValue = ModelClient(models: { ... })
}

extension DependencyValues {
    public var modelClient: ModelClient {
        get { self[ModelClient.self] }
        set { self[ModelClient.self] = newValue }
    }
}
```

### Cancellation

Private `CancelID` enum scoped to each reducer file:

```swift
private enum CancelID: Hashable {
    case streaming
    case debounce
}
```

## File organization

- **Co-location:** Reducer + View live in the same file. Helper views are `fileprivate`.
- **MARK comments:** Use `// MARK: -` to separate logical sections (Tool, Input, Output, Views, etc.)
- **One feature per file** — do not split a reducer and its view across files unless the file exceeds ~300 lines.

## Anti-patterns — do NOT do these

- **No classes** (except AppKit subclasses and Objective-C interop wrappers)
- **No protocols for variant types** — use enums for closed sets of cases. Protocols are fine for type constraints, open polymorphism, and associated-type generics.
- **No generic/reusable stores** — each feature gets its own `@Reducer`
- **No plain `[Element]` for TCA state** — use `IdentifiedArrayOf`
- **No side effects directly in reducers** — return `.run` or `.send`
- **No skipping `Sendable`** — strict concurrency is enforced
- **No singletons** — use TCA's dependency system
- **No `@Published` / `ObservableObject`** — use `@ObservableState`
- **No Combine** — this project uses Swift concurrency exclusively
- **No unnecessary file splitting** — co-locate reducer + view
