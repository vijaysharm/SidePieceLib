//
//  SidePieceApp.swift
//  SidePiece
//

import ComposableArchitecture
import SwiftUI

extension StorageKey where T == String {
    static var openAi: Self {
        .keyChainStorageKey("openai")
    }
    
    static var anthropic: Self {
        .keyChainStorageKey("anthropic")
    }
    
    static var openRouter: Self {
        .keyChainStorageKey("open_router")
    }
}

extension StorageKey where T == [RecentProject] {
    static var recent: Self {
        StorageKey(
            id: "recent_projects",
        ) { id in
            @Dependency(\.userPreferencesClient) var client
            guard let data = client.get(id) else {
                throw StorageKeyError.dataNotFound
            }
            
            @Dependency(\.jsonCoder) var coder
            return try coder.decode([RecentProject].self, from: data)
        } write: { id, list in
            @Dependency(\.jsonCoder) var coder
            let data = try coder.encode(list)
            
            @Dependency(\.userPreferencesClient) var client
            client.set(data, for: id)
        }
    }
}

enum CategoryID: String, SettingIdentifiable {
    case models
    var description: String { rawValue }
}

enum SectionID: String, SettingIdentifiable {
    case modelsApiKeys = "models.apiKeys"
    var description: String { rawValue }
}

enum ItemID: String, SettingIdentifiable {
    case modelsApiKeysOpenai = "models.apiKeys.openai"
    case modelsApiKeysAnthropic = "models.apiKeys.anthropic"
    case modelsApiKeysOpenrouter = "models.apiKeys.openrouter"
    var description: String { rawValue }
}

// MARK: - Static convenience extensions for dot-syntax

extension SettingCategory.ID {
    static var models: Self { .init(CategoryID.models) }
}

extension SettingCategory {
    static let openAiSettingItem = SettingItem(
        id: ItemID.modelsApiKeysOpenai,
        title: "OpenAI",
        description: "API key for OpenAI models (GPT-4, etc.)",
        type: .secureText(
            placeholder: "Enter your OpenAI API Key",
            .openAi
        )
    )
    
    static let anthropicSettingItem = SettingItem(
        id: ItemID.modelsApiKeysAnthropic,
        title: "Anthropic",
        description: "API key for Anthropic models (Claude, etc.)",
        type: .secureText(
            placeholder: "Enter your Anthropic API Key",
            .anthropic
        )
    )
    
    static let openRouterSettingItem = SettingItem(
        id: ItemID.modelsApiKeysOpenrouter,
        title: "OpenRouter",
        description: "API key for OpenRouter (multi-provider access)",
        type: .secureText(
            placeholder: "Enter your OpenRouter API Key",
            .openRouter
        )
    )

    static var `default`: IdentifiedArrayOf<SettingCategory> {
        [
            SettingCategory(
                id: .models,
                title: "Models",
                icon: "brain",
                sections: [
                    SettingSection(
                        id: SectionID.modelsApiKeys,
                        title: "API Keys",
                        items: [
                            openAiSettingItem,
                            anthropicSettingItem,
                            openRouterSettingItem,
                        ]
                    ),
                ]
            )
        ]
    }
}

extension ModelClient {
    public static let demo: Self = ModelClient(transformer: { registry in
        let openRouter = ModelRegistry.ProviderID(rawValue: "openrouter")
        let openAi = ModelRegistry.ProviderID(rawValue: "openai")
        var models: [Model] = []
        
        var defaultModel: Model? = nil
        if let openRouterProvider = registry.providers[openRouter] {
            let apiKey = try? StorageKey.openRouter.read()
            models.append(contentsOf: openRouterProvider.models.values.map { model in
                let id = "\(model.id.rawValue)"
                let preferredModel = "arcee-ai/trinity-mini:free"
                var settings: Set<Model.Properties> = []
                if model.id.rawValue == preferredModel {
                    settings.insert(.preferred)
                }
                let mapped: Model =  .model(
                    model,
                    provider: openRouterProvider,
                    properties: settings,
                    stream: { items, options in
                        OpenAIProvider(
                            modelId: id,
                            apiKey: apiKey ?? "",
                            baseURL: URL(string: "https://openrouter.ai/api/v1")!,
                        ).stream(items: items, options: options)
                    }
                )
                if model.id.rawValue == preferredModel {
                    defaultModel = mapped
                }
                return mapped
            })
        }
        
        if let openAiProvider = registry.providers[openAi] {
            let apiKey = try? StorageKey.openAi.read()
            models.append(contentsOf: openAiProvider.models.values.map { model in
                let id = "\(model.id.rawValue)"
                return .model(
                    model,
                    provider: openAiProvider,
                    stream: { items, options in
                        OpenAIProvider(
                            modelId: id,
                            apiKey: apiKey ?? "",
                            baseURL: URL(string: "https://api.openai.com/v1")!,
                        ).stream(items: items, options: options)
                    }
                )
            })
        }
        
        return .models(models, default: defaultModel ?? models.first!)
    })
}

public extension Agent {
    static let ask = Agent(
        name: "Ask",
        color: .green,
        icon: Image(systemName: "message"),
        tools: [
            .readFile,
            .fileSearch,
            .globFileSearch,
            .grep,
            .codebaseFileSearch,
            .listDirectory
        ]
    )
    
    static let plan = Agent(
        name: "Plan",
        color: .orange,
        icon: Image(systemName: "message"),
        tools: [
            .readFile,
            .fileSearch,
            .globFileSearch,
            .grep,
            .codebaseFileSearch,
            .listDirectory
        ]
    )
}

extension AgentClient {
    static let demo = AgentClient(agents: {
        Agents(agents: [.ask, .plan], default: .ask)
    })
}

extension MessageItemClient {
    static let demo = MessageItemClient(
        systemPrompt: { context in
            guard context.agent == .ask else {
                return nil
            }
            return """
You are a helpful coding assistant. Answer the user's questions about their codebase. Use tools only when needed. Do NOT make changes.

Project root: \(context.projectURL.path)
"""
        }
    )
}

extension RecentProjectsClient {
    static let demo = RecentProjectsClient(key: .recent)
}

struct SidePieceView: View {
    let store = Store(initialState: .loading(LoadingFeature.State(
        categories: SettingCategory.default
    ))) {
        SidePieceAppFeature()
    } withDependencies: {
        $0.modelClient = .demo
        $0.agentClient = .demo
        $0.recentProjectsClient = .demo
        $0.messageItemClient = .demo
    }
    
    var body: some View {
        SidePieceAppView(store: store)
    }
}

@main
struct SidePieceApp: App {
    var body: some Scene {
        WindowGroup {
            SidePieceView()
        }
        .windowStyle(.hiddenTitleBar)
    }
}

#Preview {
    SidePieceView()
        .frame(width: 900, height: 700)
}
