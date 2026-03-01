//
//  RecentProjectsSelection.swift
//  SidePiece
//

import ComposableArchitecture
import SwiftUI

public enum RecentProjectError: LocalizedError, Equatable, Sendable {
    case bookmarkFailed(code: Int, domain: String, message: String)

    public init(from error: Error) {
        let nsError = error as NSError
        self = .bookmarkFailed(code: nsError.code, domain: nsError.domain, message: nsError.localizedDescription)
    }

    public var errorDescription: String? {
        switch self {
        case let .bookmarkFailed(_, _, message):
            message
        }
    }
}

// MARK: - Reducer

@Reducer
public struct RecentProjectsSelectionFeature: Sendable {
    
    // MARK: - Focus
    
    public enum FocusableItem: Hashable {
        case project(UUID)
    }
    
    // MARK: - State
    
    @ObservableState
    public struct State: Equatable {
        var isLoading = true
        var recentProjects: [RecentProject] = []
        var selectedProjectID: UUID? = nil
        var focusedProjectID: UUID? = nil
        var presentDirectoryPicker: Bool = false
        
        var hasRecentProjects: Bool {
            !recentProjects.isEmpty
        }
    }
    
    // MARK: - Action
    
    public enum Action: BindableAction, Equatable {
        case binding(BindingAction<State>)
        case onAppear
        case enterKeyPressed
        case moveFocusUp
        case moveFocusDown
        case projectTapped(RecentProject)
        case projectDoubleTapped(RecentProject)
        case openDirectorySelected
        case presentDirectoryPickerChanged(Bool)
        case directoryPicked(URL)
        case recentProjectsLoaded([RecentProject])
        
        // Delegate actions for parent to handle
        case delegate(Delegate)
        
        @CasePathable
        public enum Delegate: Equatable {
            case openUrl(URL)
            case error(RecentProjectError)
        }
    }
    
    @Dependency(\.recentProjectsClient) var recentProject
    
    // MARK: - Reducer Body
    
    public var body: some ReducerOf<Self> {
        BindingReducer()
        
        Reduce { state, action in
            switch action {
            case .binding:
                return .none
                
            case .onAppear:
                state.isLoading = true
                return .run { send in
                    let recents = try? await recentProject.loadAll()
                    await send(.recentProjectsLoaded(recents ?? []))
                }
                
            case let .recentProjectsLoaded(projects):
                state.isLoading = false
                state.recentProjects = projects
                // Don't set initial focus - let user activate via keyboard or Tab
                return .none
                
            case .enterKeyPressed:
                guard let focusedID = state.focusedProjectID,
                      let project = state.recentProjects.first(where: { $0.id == focusedID }) else {
                    return .none
                }
                return .send(.projectDoubleTapped(project))
                
            case .moveFocusUp:
                let newID = previousProjectID(from: state.focusedProjectID, in: state)
                state.focusedProjectID = newID
                state.selectedProjectID = newID
                return .none
                
            case .moveFocusDown:
                let newID = nextProjectID(from: state.focusedProjectID, in: state)
                state.focusedProjectID = newID
                state.selectedProjectID = newID
                return .none
                
            case let .projectTapped(project):
                state.selectedProjectID = project.id
                state.focusedProjectID = project.id
                return .none
                
            case let .projectDoubleTapped(project):
                return .run { [recentProject, project] send in
                    do {
                        let url = try await recentProject.resolve(project)
                        await send(.delegate(.openUrl(url)))
                    } catch {
                        await send(.delegate(.error(RecentProjectError(from: error))))
                    }
                }
                
            case .openDirectorySelected:
                state.presentDirectoryPicker = true
                return .none
                
            case let .presentDirectoryPickerChanged(value):
                state.presentDirectoryPicker = value
                return .none
                
            case let .directoryPicked(url):
                return .run { [recentProject, url] send in
                    do {
                        let project = try await recentProject.add(url)
                        let resolvedUrl = try await recentProject.resolve(project)
                        await send(.delegate(.openUrl(resolvedUrl)))
                    } catch {
                        await send(.delegate(.error(RecentProjectError(from: error))))
                    }
                }
                
            case .delegate:
                return .none
            }
        }
    }
    
    // MARK: - Focus Navigation Helpers
    
    private func nextProjectID(from current: UUID?, in state: State) -> UUID? {
        let projects = state.recentProjects
        guard !projects.isEmpty else { return nil }
        
        guard let current = current,
              let currentIndex = projects.firstIndex(where: { $0.id == current }) else {
            return projects.first?.id
        }
        
        let nextIndex = (currentIndex + 1) % projects.count
        return projects[nextIndex].id
    }
    
    private func previousProjectID(from current: UUID?, in state: State) -> UUID? {
        let projects = state.recentProjects
        guard !projects.isEmpty else { return nil }
        
        guard let current = current,
              let currentIndex = projects.firstIndex(where: { $0.id == current }) else {
            return projects.last?.id
        }
        
        let previousIndex = currentIndex == 0 ? projects.count - 1 : currentIndex - 1
        return projects[previousIndex].id
    }
}

// MARK: - View

struct RecentProjectsSelectionView: View {
    @Bindable var store: StoreOf<RecentProjectsSelectionFeature>
    @FocusState private var isViewFocused: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Recent Directories")
                .font(.callout)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(store.recentProjects) { project in
                        RecentProjectRow(
                            project: project,
                            isSelected: store.selectedProjectID == project.id,
                            isKeyboardSelected: store.focusedProjectID == project.id
                        ) {
                            store.send(.projectTapped(project))
                        } onDoubleClick: {
                            store.send(.projectDoubleTapped(project))
                        }
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .focusable()
        .focusEffectDisabled()
        .focused($isViewFocused)
        .onAppear {
            isViewFocused = true
        }
        .onKeyPress(.return) {
            store.send(.enterKeyPressed)
            return .handled
        }
        .onMoveCommand { direction in
            switch direction {
            case .up:
                store.send(.moveFocusUp)
            case .down:
                store.send(.moveFocusDown)
            default:
                break
            }
        }
        .fileImporter(
            isPresented: $store.presentDirectoryPicker.sending(\.presentDirectoryPickerChanged),
            allowedContentTypes: [.directory],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case let .success(urls):
                guard let url = urls.first else { return }
                store.send(.directoryPicked(url))
            case .failure:
                break
            }
        }
    }
}

// MARK: - Recent Project Row

struct RecentProjectRow: View {
    let project: RecentProject
    let isSelected: Bool
    var isKeyboardSelected: Bool = false
    let onClick: () -> Void
    let onDoubleClick: () -> Void
    
    @State private var isHovering = false
    
    private var isHighlighted: Bool {
        isSelected || isHovering || isKeyboardSelected
    }
    
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(project.displayName)
                    .font(.headline)
                    .foregroundStyle(isHighlighted ? .white : .primary)
                    .lineLimit(1)
                
                Text(project.pathString)
                    .font(.subheadline)
                    .foregroundStyle(isHighlighted ? .white.opacity(0.85) : .secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            
            Spacer()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isHighlighted ? Color(white: 0.2) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onClick()
        }
        .onTapGesture(count: 2) {
            onDoubleClick()
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.08)) {
                isHovering = hovering
            }
        }
        .padding(1)
    }
}

// MARK: - Preview

#Preview("Recent Projects Selection") {
    RecentProjectsSelectionView(store: Store(initialState: RecentProjectsSelectionFeature.State(
        isLoading: false,
        recentProjects: [
            RecentProject(
                id: UUID(),
                url: URL(string: "file:///Users/example/project1")!,
                bookmarkData: "".data(using: .utf8)!,
                lastAccessed: Date()
            ),
            RecentProject(
                id: UUID(),
                url: URL(string: "file:///Users/example/project2")!,
                bookmarkData: "".data(using: .utf8)!,
                lastAccessed: Date()
            ),
        ]
    )) {
        RecentProjectsSelectionFeature()
    })
    .frame(width: 400, height: 300)
}
