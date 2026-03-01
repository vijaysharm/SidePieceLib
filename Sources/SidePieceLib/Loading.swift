//
//  Loading.swift
//  SidePiece
//

import ComposableArchitecture
import SwiftUI

public enum LoadingError: LocalizedError, Equatable, Sendable {
    case network(code: Int, domain: String, message: String)

    public init(from error: Error) {
        let nsError = error as NSError
        self = .network(code: nsError.code, domain: nsError.domain, message: nsError.localizedDescription)
    }

    public var errorDescription: String? {
        switch self {
        case let .network(_, _, message):
            message
        }
    }
}

@Reducer
public struct LoadingFeature: Sendable {
    @ObservableState
    public struct State: Equatable {
        public var categories: IdentifiedArrayOf<SettingCategory>
        
        public init(categories: IdentifiedArrayOf<SettingCategory>) {
            self.categories = categories
        }
    }
    
    public enum Action: Equatable {
        case onAppear
        case delegate(DelegateAction)
        
        @CasePathable
        public enum DelegateAction: Equatable {
            case ready(RootFeature.State)
            case failed(LoadingError)
        }
    }
    
    @Dependency(\.modelClient) var modelClient
    @Dependency(\.agentClient) var agentClient
    @Dependency(\.toolRegistryClient) var toolRegistryClient
    @Dependency(\.recentProjectsClient) var recentProjectsClient
    @Dependency(\.conversationStorageClient) var conversationStorageClient

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                let settings = state.categories
                return .run { send in
                    // TODO: Handle the case where loading fails
                    let models = try await modelClient.models()
                    let agents = try await agentClient.agents()
                    agents.agents.forEach {
                        $0.tools.forEach {
                            toolRegistryClient.register($0)
                        }
                    }
                    let recentProjects = (try? await recentProjectsClient.loadAll()) ?? []
                    var urls: [URL] = []
                    for project in recentProjects {
                        if let url = try? await recentProjectsClient.resolve(project) {
                            _ = url.startAccessingSecurityScopedResource()
                            urls.append(url)
                        }
                    }

                    // Load first page of saved conversations for each project
                    var savedConversations: [URL: [ConversationDTO]] = [:]
                    for url in urls {
                        let page = try? await conversationStorageClient.loadPage(url, 0, ProjectFeature.State.pageSize)
                        if let page, !page.isEmpty {
                            savedConversations[url] = page
                        }
                    }

                    let state = RootFeature.State(
                        project: ProjectFeature.State(
                            models: models,
                            agents: agents,
                            projectURLs: urls,
                            savedConversations: savedConversations
                        ),
                        settings: SettingsFeature.State(
                            categories: settings
                        )
                    )
                    await send(.delegate(.ready(state)))
                } catch: { error, send in
                    await send(.delegate(.failed(LoadingError(from: error))))
                }
            case .delegate:
                return .none
            }
        }
    }
}

struct LoadingView: View {
    @Bindable var store: StoreOf<LoadingFeature>
    
    var body: some View {
        ZStack {
            EmptyView()
        }
        .onAppear {
            store.send(.onAppear)
        }
    }
}
