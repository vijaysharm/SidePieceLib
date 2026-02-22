//
//  SplashScreen.swift
//  SidePiece
//

import ComposableArchitecture
import SwiftUI

public struct ActionButton: Equatable, Identifiable {
    public var id: String { title }
    let icon: String
    let title: String
    let action: SplashScreenFeature.Action
}

// MARK: - Reducer

@Reducer
public struct SplashScreenFeature: Sendable {
    
    // MARK: - Focus
    
    public enum FocusableItem: Hashable {
        case actionButton(String)
        case recentProject(UUID)
    }
    
    // MARK: - State
    
    @ObservableState
    public struct State: Equatable {
        var appIcon: String
        var appTitle: String
        var appVersion: String
        var actionButtons: [ActionButton] = []
        var recentProjectsSelection = RecentProjectsSelectionFeature.State()
        var focusedItem: FocusableItem? = nil
        
        var isLoading: Bool {
            recentProjectsSelection.isLoading
        }
        
        var hasRecentProjects: Bool {
            recentProjectsSelection.hasRecentProjects
        }
    }
    
    // MARK: - Action
    
    public enum Action: BindableAction, Equatable {
        case binding(BindingAction<State>)
        case onAppear
        case enterKeyPressed
        case moveFocusUp
        case moveFocusDown
        case openDirectorySelected
        case openSettingsSelected
        case recentProjectsSelection(RecentProjectsSelectionFeature.Action)
    }
    
    // MARK: - Reducer Body
    
    public var body: some ReducerOf<Self> {
        BindingReducer()
        
        Scope(state: \.recentProjectsSelection, action: \.recentProjectsSelection) {
            RecentProjectsSelectionFeature()
        }
        
        Reduce { state, action in
            switch action {
            case .binding:
                return .none
                
            case .onAppear:
                return .send(.recentProjectsSelection(.onAppear))
                
            case .recentProjectsSelection(.recentProjectsLoaded):
                // Don't set initial focus - let user activate via keyboard or Tab
                return .none
                
            case .recentProjectsSelection(.delegate(.openUrl)):
                return .none
                
            case .recentProjectsSelection(.delegate(.error)):
                return .none
                
            case .recentProjectsSelection:
                return .none
                
            case .enterKeyPressed:
                guard let focusedItem = state.focusedItem else { return .none }
                
                switch focusedItem {
                case let .actionButton(buttonID):
                    guard let button = state.actionButtons.first(where: { $0.id == buttonID }) else {
                        return .none
                    }
                    return .send(button.action)
                    
                case let .recentProject(projectID):
                    guard let project = state.recentProjectsSelection.recentProjects.first(where: { $0.id == projectID }) else {
                        return .none
                    }
                    return .send(.recentProjectsSelection(.projectDoubleTapped(project)))
                }
                
            case .moveFocusUp:
                state.focusedItem = previousFocusableItem(from: state.focusedItem, in: state)
                // Sync with child state if it's a project
                if case let .recentProject(id) = state.focusedItem {
                    state.recentProjectsSelection.focusedProjectID = id
                }
                return .none
                
            case .moveFocusDown:
                state.focusedItem = nextFocusableItem(from: state.focusedItem, in: state)
                // Sync with child state if it's a project
                if case let .recentProject(id) = state.focusedItem {
                    state.recentProjectsSelection.focusedProjectID = id
                }
                return .none
                
            case .openDirectorySelected:
                return .send(.recentProjectsSelection(.openDirectorySelected))
                
            case .openSettingsSelected:
                return .none
            }
        }
    }
    
    // MARK: - Focus Navigation Helpers
    
    private func allFocusableItems(in state: State) -> [FocusableItem] {
        var items: [FocusableItem] = []
        
        // Action buttons (left panel)
        items.append(contentsOf: state.actionButtons.map { .actionButton($0.id) })
        
        // Recent projects (right panel, if any)
        items.append(contentsOf: state.recentProjectsSelection.recentProjects.map { .recentProject($0.id) })
        
        return items
    }
    
    private func nextFocusableItem(from current: FocusableItem?, in state: State) -> FocusableItem? {
        let items = allFocusableItems(in: state)
        guard !items.isEmpty else { return nil }
        
        guard let current = current,
              let currentIndex = items.firstIndex(of: current) else {
            return items.first
        }
        
        let nextIndex = (currentIndex + 1) % items.count
        return items[nextIndex]
    }
    
    private func previousFocusableItem(from current: FocusableItem?, in state: State) -> FocusableItem? {
        let items = allFocusableItems(in: state)
        guard !items.isEmpty else { return nil }
        
        guard let current = current,
              let currentIndex = items.firstIndex(of: current) else {
            return items.last
        }
        
        let previousIndex = currentIndex == 0 ? items.count - 1 : currentIndex - 1
        return items[previousIndex]
    }
}

// MARK: - View

struct SplashScreenView: View {
    @Bindable var store: StoreOf<SplashScreenFeature>
    @FocusState private var isViewFocused: Bool
    
    var body: some View {
        if store.isLoading {
            ZStack {
                ProgressView()
                    .controlSize(.small)
            }
            .onAppear {
                store.send(.onAppear)
            }
        } else {
            HSplitView {
                leftPanel
                    .padding()
                
                if store.hasRecentProjects {
                    rightPanel
                        .padding(.horizontal)
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
                isPresented: $store.recentProjectsSelection.presentDirectoryPicker.sending(\.recentProjectsSelection.presentDirectoryPickerChanged),
                allowedContentTypes: [.directory],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case let .success(urls):
                    guard let url = urls.first else { return }
                    store.send(.recentProjectsSelection(.directoryPicked(url)))
                case .failure:
                    break
                }
            }
        }
    }
    
    // MARK: - Left Panel
    
    private var leftPanel: some View {
        ZStack {
            Rectangle()
                .fill(.clear)
            VStack() {
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                    .frame(width: 128, height: 128)
                    Image(systemName: store.appIcon)
                        .resizable()
                        .frame(width: 64, height: 64)
                        .foregroundStyle(.black)
                }
                Text(store.appTitle)
                    .font(.title)
                    .foregroundStyle(.primary)
                Text(store.appVersion)
                    .font(.title2)
                    .foregroundStyle(.secondary)
                actionButtonsSection
                    .padding(.top)
            }
        }
    }
    
    private var actionButtonsSection: some View {
        VStack(spacing: 0) {
            ForEach(store.actionButtons) { button in
                ActionButtonRow(
                    button: button,
                    isSelected: store.focusedItem == .actionButton(button.id)
                ) {
                    store.send(button.action)
                }
                
                if button.id != store.actionButtons.last?.id {
                    Divider()
                        .padding(.horizontal, 16)
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color(white: 0.3), lineWidth: 0.5)
        )
        .frame(maxWidth: 400)
    }
    
    // MARK: - Right Panel
    
    private var rightPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Recent Directories")
                .font(.callout)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(store.recentProjectsSelection.recentProjects) { project in
                        RecentProjectRow(
                            project: project,
                            isSelected: store.recentProjectsSelection.selectedProjectID == project.id,
                            isKeyboardSelected: store.focusedItem == .recentProject(project.id)
                        ) {
                            store.send(.recentProjectsSelection(.projectTapped(project)))
                        } onDoubleClick: {
                            store.send(.recentProjectsSelection(.projectDoubleTapped(project)))
                        }
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }
}

// MARK: - Action Button Row

private struct ActionButtonRow: View {
    let button: ActionButton
    var isSelected: Bool = false
    let action: () -> Void
    
    @State private var isHovering = false
    
    private var isHighlighted: Bool {
        isSelected || isHovering
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: button.icon)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(.secondary)
                .frame(width: 24)
            
            Text(button.title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.primary)
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isHighlighted ? Color(white: 0.25) : Color.clear)
                .padding(2)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            action()
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovering = hovering
            }
        }
    }
}

// MARK: - Preview

#Preview("With Recent Projects") {
    SplashScreenView(store: Store(initialState: SplashScreenFeature.State(
        appIcon: "sidebar.right",
        appTitle: "SidePiece",
        appVersion: "Version 1.0",
        actionButtons: [
            ActionButton(
                icon: "folder",
                title: "Open Directory...",
                action: .openDirectorySelected
            ),
            ActionButton(
                icon: "gear",
                title: "Settings",
                action: .openSettingsSelected
            )
        ],
        recentProjectsSelection: RecentProjectsSelectionFeature.State(
            isLoading: false,
            recentProjects: [
                RecentProject(
                    id: UUID(),
                    url: URL(string: "file:///Users/example/project")!,
                    bookmarkData: "".data(using: .utf8)!,
                    lastAccessed: Date()
                ),
            ]
        )
    )) {
        SplashScreenFeature()
    })
    .frame(width: 800, height: 550)
}

#Preview("No Recent Projects") {
    SplashScreenView(store: Store(initialState: SplashScreenFeature.State(
        appIcon: "sidebar.right",
        appTitle: "SidePiece",
        appVersion: "Version 1.0",
        actionButtons: [
            ActionButton(
                icon: "folder",
                title: "Open Directory...",
                action: .openDirectorySelected
            ),
            ActionButton(
                icon: "gear",
                title: "Settings",
                action: .openSettingsSelected
            )
        ],
        recentProjectsSelection: RecentProjectsSelectionFeature.State(
            isLoading: false,
            recentProjects: []
        )
    )) {
        SplashScreenFeature()
    })
    .frame(width: 500, height: 550)
}
