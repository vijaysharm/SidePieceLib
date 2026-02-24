//
//  Project.swift
//  SidePiece

import ComposableArchitecture
import SwiftUI

public struct SearchLoadedConversation: Equatable {
    let dto: ConversationDTO
    let projectURL: URL
    let projectID: UUID
}

@Reducer
public struct ProjectFeature: Sendable {
    @ObservableState
    public struct State: Equatable {
        var models: Models
        var agents: Agents

        var projectItems: IdentifiedArrayOf<ProjectItemFeature.State> = []
        var conversations: IdentifiedArrayOf<ConversationFeature.State> = []

        var activeProjectID: ProjectItemFeature.State.ID? = nil
        var selectedConversationID: ConversationFeature.State.ID? = nil
        var hoveringID: ConversationFeature.State.ID? = nil
        var hoveringProjectID: ProjectItemFeature.State.ID? = nil

        var searchFilter: String = ""
        var filteredConversationIDs: Set<UUID>? = nil

        // Pagination
        var loadedConversationCounts: [ProjectItemFeature.State.ID: Int] = [:]
        var hasMoreConversations: [ProjectItemFeature.State.ID: Bool] = [:]
        static let pageSize = 10

        @Shared(.appStorage("splitViewVisibility"))
        var splitViewVisibility: NavigationSplitViewVisibility = .automatic

        var activeProject: ProjectItemFeature.State? {
            activeProjectID.flatMap { projectItems[id: $0] }
        }

        var selectedConversation: ConversationFeature.State? {
            selectedConversationID.flatMap { conversations[id: $0] }
        }

        func conversations(for projectID: ProjectItemFeature.State.ID) -> [ConversationFeature.State] {
            guard let project = projectItems[id: projectID] else { return [] }
            return project.conversationIDs.compactMap { conversations[id: $0] }
        }

        var hasProjects: Bool { !projectItems.isEmpty }

        var isFiltering: Bool {
            !searchFilter.isEmpty
        }

        var filterResultCount: Int? {
            filteredConversationIDs?.count
        }

        init(
            models: Models,
            agents: Agents,
            projectURLs: [URL] = [],
            savedConversations: [URL: [ConversationDTO]] = [:]
        ) {
            var projectItems: IdentifiedArrayOf<ProjectItemFeature.State> = []
            var conversations: IdentifiedArrayOf<ConversationFeature.State> = []
            var loadedCounts: [UUID: Int] = [:]
            var hasMore: [UUID: Bool] = [:]

            for url in projectURLs {
                guard !projectItems.contains(where: {
                    $0.url.standardizedFileURL == url.standardizedFileURL
                }) else { continue }

                let projectID = UUID()
                var projectItem = ProjectItemFeature.State(
                    id: projectID, url: url, isExpanded: false
                )

                // Rehydrate saved conversations for this project
                let saved = savedConversations[url] ?? []
                for dto in saved {
                    let state = dto.toState(project: url, models: models, agents: agents)
                    conversations.append(state)
                    projectItem.conversationIDs.append(state.id)
                }

                loadedCounts[projectID] = saved.count
                hasMore[projectID] = saved.count >= Self.pageSize

                if saved.isEmpty {
                    let newConversation = createNewConversation(project: url, models: models, agents: agents)
                    conversations.insert(newConversation, at: 0)
                    projectItem.conversationIDs.insert(newConversation.id, at: 0)
                }

                projectItems.append(projectItem)
            }

            self.projectItems = projectItems
            self.conversations = conversations
            self.models = models
            self.agents = agents
            self.loadedConversationCounts = loadedCounts
            self.hasMoreConversations = hasMore
        }
    }

    public enum Action: Equatable {
        case onAppear
        case addProject(URL)
        case newAgent
        case setHovering(ConversationFeature.State.ID?)
        case setProjectHovering(ProjectItemFeature.State.ID?)
        case removeProject(id: UUID, url: URL)
        case selectConversation(ConversationFeature.State.ID?)
        case searchFilterChanged(String)
        case splitViewVisibilityChanged(NavigationSplitViewVisibility)
        case loadMoreConversations(ProjectItemFeature.State.ID)
        case deleteConversation(ConversationFeature.State.ID)
        case projectItems(IdentifiedActionOf<ProjectItemFeature>)
        case conversations(IdentifiedActionOf<ConversationFeature>)
        case delegate(DelegateAction)
        case `internal`(InternalAction)
        case applyModelSelection(
            source: ModelSelectionFeature.State.Source,
            model: Model
        )

        @CasePathable
        public enum DelegateAction: Equatable {
            case selectDirectory
            case settings
            case viewImage(URL)
            case confirmDeleteConversation(id: UUID, title: String)
            case confirmRemoveProject(id: UUID, title: String, url: URL)
        }

        @CasePathable
        public enum InternalAction: Equatable {
            case indexProject(URL)
            case performSearch(String)
            case searchCompleted(String, Set<UUID>, [SearchLoadedConversation])
            case saveConversation(ConversationFeature.State.ID)
            case saveDraft(ConversationFeature.State.ID)
            case loadMoreCompleted(ProjectItemFeature.State.ID, [ConversationDTO])
        }
    }

    @Dependency(\.projectClient) var projectClient
    @Dependency(\.recentProjectsClient) var recentProjectsClient
    @Dependency(\.conversationStorageClient) var conversationStorageClient
    @Dependency(\.mainQueue) var mainQueue
    @Dependency(\.uuid) var uuid

    enum CancelID {
        case indexer
        case search
    }

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                // Activate first project, select first conversation
                guard state.activeProjectID == nil else { return .none }
                guard let firstProject = state.projectItems.first else { return .none }
                
                state.activeProjectID = firstProject.id
                if state.selectedConversationID == nil,
                   let firstConvoID = firstProject.conversationIDs.first {
                    state.selectedConversationID = firstConvoID
                    state.projectItems[id: firstProject.id]?.isExpanded = true
                }
                
                return .send(.internal(.indexProject(firstProject.url)))

            case let .addProject(url):
                _ = url.startAccessingSecurityScopedResource()
                // Guard against duplicate projects (same URL path)
                if let existing = state.projectItems.first(where: {
                    $0.url.standardizedFileURL == url.standardizedFileURL
                }) {
                    state.activeProjectID = existing.id
                    state.projectItems[id: existing.id]?.isExpanded = true
                    // Select the first conversation in the existing project if none selected
                    if let firstConvoID = existing.conversationIDs.first {
                        state.selectedConversationID = firstConvoID
                    }
                    return .send(.internal(.indexProject(url)))
                }

                let projectID = uuid()
                var projectItem = ProjectItemFeature.State(
                    id: projectID,
                    url: url,
                    isExpanded: true
                )

                // Create initial conversation for the project if models are loaded
                let conversation = Self.createNewConversation(project: url, models: state.models, agents: state.agents)
                state.conversations.append(conversation)
                projectItem.conversationIDs.append(conversation.id)
                state.selectedConversationID = conversation.id

                state.projectItems.append(projectItem)
                state.activeProjectID = projectID

                return .merge(
                    .send(.internal(.indexProject(url))),
                    .run { [recentProjectsClient] _ in
                        _ = try? await recentProjectsClient.add(url)
                    }
                )

            case .newAgent:
                guard let activeProjectID = state.activeProjectID,
                      let activeProject = state.projectItems[id: activeProjectID]
                else { return .none }

                // If there's already an empty conversation in this project, select it
                let projectConversations = state.conversations(for: activeProjectID)
                if let emptyConvo = projectConversations.first(where: { $0.isEmpty }) {
                    state.selectedConversationID = emptyConvo.id
                    return .none
                }

                let conversation = Self.createNewConversation(project: activeProject.url, models: state.models, agents: state.agents)
                state.conversations.insert(conversation, at: 0)
                state.projectItems[id: activeProjectID]?.conversationIDs.insert(conversation.id, at: 0)
                state.selectedConversationID = conversation.id
                return .none

            case let .setHovering(id):
                state.hoveringID = id
                return .none

            case let .setProjectHovering(id):
                state.hoveringProjectID = id
                return .none

            case let .removeProject(id, projectURL):
                guard let project = state.projectItems[id: id] else { return .none }

                // Collect conversation IDs belonging to this project
                let conversationIDsToRemove = Set(project.conversationIDs)

                // Remove conversations from state
                for cid in conversationIDsToRemove {
                    state.conversations.remove(id: cid)
                }

                // Clean up filtered IDs
                if var filtered = state.filteredConversationIDs {
                    filtered.subtract(conversationIDsToRemove)
                    state.filteredConversationIDs = filtered
                }

                // Remove project
                state.projectItems.remove(id: id)
                state.loadedConversationCounts.removeValue(forKey: id)
                state.hasMoreConversations.removeValue(forKey: id)

                // Clear hovering if it matched
                if state.hoveringProjectID == id {
                    state.hoveringProjectID = nil
                }

                // If the active project was removed, select the next one
                if state.activeProjectID == id {
                    if let nextProject = state.projectItems.first {
                        state.activeProjectID = nextProject.id
                        state.projectItems[id: nextProject.id]?.isExpanded = true
                        state.selectedConversationID = nextProject.conversationIDs.first
                    } else {
                        state.activeProjectID = nil
                        state.selectedConversationID = nil
                    }
                } else if let selectedID = state.selectedConversationID,
                          conversationIDsToRemove.contains(selectedID) {
                    // Selected conversation was in the removed project
                    if let activeID = state.activeProjectID,
                       let activeProject = state.projectItems[id: activeID] {
                        state.selectedConversationID = activeProject.conversationIDs.first
                    } else {
                        state.selectedConversationID = nil
                    }
                }

                return .run { [recentProjectsClient, conversationStorageClient] _ in
                    try? await conversationStorageClient.deleteAll(projectURL)
                    guard let all = try? await recentProjectsClient.loadAll() else {
                        return
                    }
                    
                    guard let match = all.first(where: {
                        $0.pathString == projectURL.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
                    }) else { return }
                    
                    try? await recentProjectsClient.remove(match.id)
                }.cancellable(id: CancelID.indexer, cancelInFlight: true)

            case let .selectConversation(conversationID):
                state.selectedConversationID = conversationID

                // Determine which project owns this conversation and activate it
                guard let conversationID else { return .none }
                guard let owningProject = state.projectItems.first(where: {
                    $0.conversationIDs.contains(conversationID)
                }) else { return .none }
                guard owningProject.id != state.activeProjectID else { return .none }

                state.activeProjectID = owningProject.id
                return .send(.internal(.indexProject(owningProject.url)))

            case let .searchFilterChanged(text):
                state.searchFilter = text
                guard !text.isEmpty else {
                    state.filteredConversationIDs = nil
                    return .cancel(id: CancelID.search)
                }
                return .send(.internal(.performSearch(text)))
                    .debounce(id: CancelID.search, for: .milliseconds(300), scheduler: mainQueue)

            case let .splitViewVisibilityChanged(visibility):
                state.$splitViewVisibility.withLock { $0 = visibility }
                return .none

            case let .internal(.indexProject(url)):
                return .run { _ in
                    for await _ in projectClient.index(url) {}
                }.cancellable(id: CancelID.indexer, cancelInFlight: true)

            case let .internal(.performSearch(term)):
                let loadedItems = state.conversations
                    .filter { !$0.isEmpty }
                    .map { ConversationSearchItem(id: $0.id, title: $0.displayTitle) }
                let loadedIDs = Set(state.conversations.ids)
                let projects = state.projectItems.map { ($0.id, $0.url) }

                return .run { [projectClient, conversationStorageClient] send in
                    var allItems = loadedItems
                    var unloadedMap: [UUID: (url: URL, projectID: UUID)] = [:]

                    for (projectID, url) in projects {
                        guard let index = try? await conversationStorageClient.loadIndex(url) else { continue }
                        for entry in index.entries where !loadedIDs.contains(entry.id) {
                            allItems.append(ConversationSearchItem(id: entry.id, title: entry.title))
                            unloadedMap[entry.id] = (url, projectID)
                        }
                    }

                    let results = await projectClient.search(term, allItems)
                    let resultSet = Set(results)

                    var loaded: [SearchLoadedConversation] = []
                    for id in results {
                        if let info = unloadedMap[id],
                           let dto = try? await conversationStorageClient.load(id, info.url) {
                            loaded.append(SearchLoadedConversation(
                                dto: dto, projectURL: info.url, projectID: info.projectID
                            ))
                        }
                    }

                    await send(.internal(.searchCompleted(term, resultSet, loaded)))
                }.cancellable(id: CancelID.search, cancelInFlight: true)

            case let .internal(.searchCompleted(term, ids, loadedConversations)):
                guard term == state.searchFilter else { return .none }
                state.filteredConversationIDs = ids

                for item in loadedConversations {
                    guard !state.conversations.contains(where: { $0.id == item.dto.id }) else { continue }
                    let conversationState = item.dto.toState(project: item.projectURL, models: state.models, agents: state.agents)
                    state.conversations.append(conversationState)
                    if state.projectItems[id: item.projectID] != nil {
                        let insertIndex = min(1, state.projectItems[id: item.projectID]!.conversationIDs.count)
                        state.projectItems[id: item.projectID]!.conversationIDs.insert(conversationState.id, at: insertIndex)
                    }
                }

                return .none

            case let .internal(.loadMoreCompleted(projectID, dtos)):
                guard var projectItem = state.projectItems[id: projectID] else { return .none }
                let project = projectItem.url
                for dto in dtos {
                    guard !state.conversations.contains(where: { $0.id == dto.id }) else { continue }
                    let conversationState = dto.toState(project: project, models: state.models, agents: state.agents)
                    state.conversations.append(conversationState)
                    projectItem.conversationIDs.append(conversationState.id)
                }
                state.projectItems[id: projectID] = projectItem
                let currentCount = (state.loadedConversationCounts[projectID] ?? 0) + dtos.count
                state.loadedConversationCounts[projectID] = currentCount
                state.hasMoreConversations[projectID] = dtos.count >= State.pageSize
                return .none

            case let .loadMoreConversations(projectID):
                guard let projectItem = state.projectItems[id: projectID] else { return .none }
                let offset = state.loadedConversationCounts[projectID] ?? 0
                let url = projectItem.url
                return .run { [conversationStorageClient] send in
                    let dtos = try await conversationStorageClient.loadPage(url, offset, State.pageSize)
                    await send(.internal(.loadMoreCompleted(projectID, dtos)))
                }

            case let .deleteConversation(conversationID):
                guard let conversation = state.conversations[id: conversationID] else { return .none }
                let projectURL = conversation.project

                // Remove from project item's conversation IDs
                for i in state.projectItems.indices {
                    state.projectItems[i].conversationIDs.removeAll { $0 == conversationID }
                }

                // If this was the selected conversation, select another
                if state.selectedConversationID == conversationID {
                    state.selectedConversationID = state.projectItems
                        .first(where: { $0.id == state.activeProjectID })?
                        .conversationIDs.first
                }

                state.conversations.remove(id: conversationID)

                return .run { [conversationStorageClient] _ in
                    try? await conversationStorageClient.delete(conversationID, projectURL)
                }

            case let .conversations(.element(id: _, action: .delegate(.viewImage(url)))):
                return .send(.delegate(.viewImage(url)))

            case let .applyModelSelection(source, model):
                return .send(.conversations(.element(
                    id: source.conversationId,
                    action: .applyModelSelection(source: source, model: model)
                )))

            case .internal:
                return .none
            case .delegate:
                return .none
            case .projectItems:
                return .none
            case .conversations:
                return .none
            }
        }
        .forEach(\.projectItems, action: \.projectItems) {
            ProjectItemFeature()
        }
        .forEach(\.conversations, action: \.conversations) {
            ConversationFeature()
        }
        ConversationPersistenceFeature()
    }

    private static func createNewConversation(
        project: URL,
        models: Models,
        agents: Agents
    ) -> ConversationFeature.State {
        ConversationFeature.State(
            project: project,
            mainTextView: ContextInputFeature.State(
                inputField: TextInputFeature.State(
                    maxLines: 3,
                    font: .monospacedSystemFont(ofSize: 15, weight: .regular),
                    fontForegroundColor: .white,
                    lineSpacing: 4,
                    placeholder: "'@' for context menu"
                ),
                images: ContextImageSelectionFeature.State(),
                agentToolbar: ContextAgentToolbarFeature.State(models: models, agents: agents)
            ),
            contextMenu: ContextOverlayFeature.State(project: project)
        )
    }
}

struct ProjectView: View {
    @Bindable var store: StoreOf<ProjectFeature>
    @Environment(\.theme) private var theme

    var body: some View {
        NavigationSplitView(
            columnVisibility: $store.splitViewVisibility.sending(\.splitViewVisibilityChanged)
        ) {
            VStack(spacing: 0) {
                // Search field
                TextField(
                    "Search Agents...",
                    text: $store.searchFilter.sending(\.searchFilterChanged)
                )
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(theme.border, lineWidth: 1)
                )
                .disabled(!store.hasProjects)
                .padding(.horizontal, 12)
                .padding(.top, 12)

                // New Agent button
                Button {
                    store.send(.newAgent)
                } label: {
                    Text("New Agent")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(theme.border, lineWidth: 1)
                )
                .disabled(!store.hasProjects)
                .padding(.horizontal, 12)
                .padding(.top, 8)

                // Section header
                HStack {
                    Text("Projects")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)

                    if let count = store.filterResultCount {
                        Text("(\(count) found)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

                    Spacer()

                    Button {
                        store.send(.delegate(.selectDirectory))
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.top, 16)
                .padding(.bottom, 8)

                // Projects tree
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(store.projectItems) { project in
                            ProjectSectionView(
                                store: store,
                                projectID: project.id
                            )
                        }
                    }
                    .padding(.horizontal, 8)
                }
                HStack {
                    Button {
                        store.send(.delegate(.settings))
                    } label: {
                        Label("Settings", systemImage: "gear")
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                .padding()
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 300, max: 1800)
        } detail: {
            if let selectedID = store.selectedConversationID, let conversationStore = store.scope(
                state: \.conversations[id: selectedID],
                action: \.conversations[id: selectedID]
            ) {
                ConversationView(store: conversationStore)
                    .id(selectedID)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 36))
                        .foregroundStyle(.tertiary)
                    Text("Open a project to get started")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            store.send(.onAppear)
        }
        .frame(minWidth: 660)
        .navigationTitle("")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Button {
                    store.send(.delegate(.selectDirectory))
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "folder.fill")
                            .font(.callout)
                        if let activeProject = store.activeProject {
                            Text(activeProject.displayName)
                                .font(.callout)
                        } else {
                            Text("No Project")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 12)
                    .frame(minWidth: 200)
                }
                .buttonStyle(.plain)
           }

            if store.splitViewVisibility == .detailOnly {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        store.send(.newAgent)
                    } label: {
                        Image(systemName: "plus.message")
                    }
                    .disabled(!store.hasProjects)
                    .help("New Agent")
                }
            }
        }
        .toolbarTitleDisplayMode(.inline)
    }
}

// MARK: - Project Section View

struct ProjectSectionView: View {
    let store: StoreOf<ProjectFeature>
    let projectID: ProjectItemFeature.State.ID
    @Environment(\.theme) private var theme

    private var isProjectHovered: Bool {
        store.hoveringProjectID == projectID
    }

    var body: some View {
        if let project = store.projectItems[id: projectID] {
            VStack(spacing: 2) {
                // Project header row
                HStack(spacing: 0) {
                    Button {
                        store.send(.projectItems(.element(
                            id: project.id, action: .toggleExpanded
                        )))
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: project.isExpanded ? "chevron.down" : "chevron.right")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                                .frame(width: 12)

                            Image(systemName: "folder.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)

                            Text(project.displayName)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(.primary)
                                .lineLimit(1)

                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if isProjectHovered {
                        Menu {
                            Button(role: .destructive) {
                                store.send(.delegate(.confirmRemoveProject(
                                    id: project.id,
                                    title: project.displayName,
                                    url: project.url
                                )))
                            } label: {
                                Label("Remove Project", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 6)
                                .padding(.horizontal, 8)
                                .contentShape(Rectangle())
                        }
                        .padding(.vertical, -6)
                        .padding(.horizontal, -8)
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isProjectHovered ? theme.hoverFill : Color.clear)
                )
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.04)) {
                        _ = store.send(.setProjectHovering(hovering ? projectID : nil))
                    }
                }

                // Conversations under this project
                let shouldShowConversations = project.isExpanded || store.isFiltering
                if shouldShowConversations {
                    ForEach(project.conversationIDs, id: \.self) { conversationID in
                        if let conversationStore = store.scope(
                            state: \.conversations[id: conversationID],
                            action: \.conversations[id: conversationID]
                        ) {
                            let isVisible = store.filteredConversationIDs == nil ||
                                store.filteredConversationIDs?.contains(conversationID) == true

                            if isVisible {
                                ConversationRowView(
                                    store: conversationStore,
                                    isSelected: store.selectedConversationID == conversationID,
                                    isHovered: store.hoveringID == conversationID,
                                    onSelect: {
                                        store.send(.selectConversation(conversationID))
                                    },
                                    onHover: { hovering in
                                        let hovered: ConversationFeature.State.ID? = hovering ? conversationID : nil
                                        store.send(.setHovering(hovered))
                                    },
                                    onDelete: {
                                        if let conversation = store.conversations[id: conversationID] {
                                            store.send(.delegate(.confirmDeleteConversation(
                                                id: conversationID,
                                                title: conversation.displayTitle
                                            )))
                                        }
                                    }
                                )
                                .padding(.leading, 20)
                                .id(conversationID)
                            }
                        }
                    }

                    // Load more button
                    if store.hasMoreConversations[projectID] == true {
                        Button {
                            store.send(.loadMoreConversations(projectID))
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.down.circle")
                                    .font(.system(size: 11))
                                Text("Load more")
                                    .font(.system(size: 12))
                            }
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, 20)
                    }
                }
            }
        }
    }
}

// MARK: - Conversation Row View

struct ConversationRowView: View {
    let store: StoreOf<ConversationFeature>
    let isSelected: Bool
    let isHovered: Bool
    let onSelect: () -> Void
    let onHover: (Bool) -> Void
    var onDelete: (() -> Void)? = nil

    @Environment(\.theme) private var theme
    @FocusState private var isRenameFocused: Bool

    private var isRenaming: Bool {
        store.renameText != nil
    }

    var body: some View {
        let rowContent = HStack(spacing: 10) {
            store.icon
                .frame(width: 14, height: 14)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(isSelected ? .white : .secondary)

            // Title - inline rename or display
            if let renameText = store.renameText {
                TextField("", text: Binding(
                    get: { renameText },
                    set: { store.send(.renameTextChanged($0)) }
                ))
                .focused($isRenameFocused)
                .onSubmit { store.send(.commitRename) }
                .onExitCommand { store.send(.cancelRename) }
                .onAppear { isRenameFocused = true }
                .font(.subheadline)
                .textFieldStyle(.plain)
                .lineLimit(1)
            } else {
                Group {
                    if store.isDraft {
                        (Text("Draft: ") + Text(store.draftPreview).italic())
                    } else {
                        Text(store.displayTitle)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(isSelected ? .white : .primary)
                .lineLimit(1)
                .truncationMode(.tail)
            }

            if !isRenaming {
                Spacer()

                // Hover actions or time
                if isHovered && !store.rowActions.isEmpty {
                    Menu {
                        ForEach(store.rowActions) { action in
                            Button(role: action.role) {
                                switch action {
                                case .rename:
                                    store.send(.beginRename)
                                case .delete:
                                    onDelete?()
                                }
                            } label: {
                                Label(action.title, systemImage: action.systemImage)
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 10)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, -8)
                    .padding(.trailing, -10)
                } else {
                    Text("\(store.displayTime)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? theme.selectedFill : (isHovered ? theme.hoverFill : Color.clear))
        )
        .contentShape(Rectangle())
        .onChange(of: isRenameFocused) { _, focused in
            if !focused && isRenaming {
                store.send(.commitRename)
            }
        }

        Group {
            if isRenaming {
                rowContent
            } else {
                Button(action: onSelect) {
                    rowContent
                }
                .buttonStyle(.plain)
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.04)) {
                onHover(hovering)
            }
        }
    }
}
