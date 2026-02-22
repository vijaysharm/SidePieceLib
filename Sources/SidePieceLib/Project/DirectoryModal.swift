//
//  DirectoryModal.swift
//  SidePiece
//

import ComposableArchitecture
import SwiftUI

@Reducer
public struct DirectoryModalFeature: Sendable {
    @ObservableState
    public struct State: Equatable {
        var recentProjectsSelection = RecentProjectsSelectionFeature.State()
    }
    
    public enum Action: Equatable {
        case recentProjectsSelection(RecentProjectsSelectionFeature.Action)
        case cancel
        case confirm
    }
    
    public var body: some ReducerOf<Self> {
        Scope(state: \.recentProjectsSelection, action: \.recentProjectsSelection) {
            RecentProjectsSelectionFeature()
        }
        
        Reduce { state, action in
            switch action {
            case .recentProjectsSelection(.delegate(.openUrl)):
                return .none
                
            case .recentProjectsSelection(.delegate(.error)):
                return .none
                
            case .recentProjectsSelection:
                return .none
                
            case .cancel:
                return .none
                
            case .confirm:
                guard let selectedID = state.recentProjectsSelection.selectedProjectID,
                      let project = state.recentProjectsSelection.recentProjects.first(where: { $0.id == selectedID }) else {
                    return .none
                }
                return .send(.recentProjectsSelection(.projectDoubleTapped(project)))
            }
        }
    }
}

struct DirectoryModalView: View {
    @Bindable var store: StoreOf<DirectoryModalFeature>
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RecentProjectsSelectionView(
                store: store.scope(
                    state: \.recentProjectsSelection,
                    action: \.recentProjectsSelection
                )
            )
            .background(.black.opacity(0.1))
            
            HStack {
                Button("Add Directory") {
                    store.send(.recentProjectsSelection(.openDirectorySelected))
                }
                
                Spacer()
                
                Button(role: .cancel) {
                    store.send(.cancel)
                } label: {
                    Text("Cancel")
                }
                
                Button/*(role: .confirm)*/ {
                    store.send(.confirm)
                } label: {
                    Text("OK")
                }
                .disabled(store.recentProjectsSelection.selectedProjectID == nil)
            }
            .padding(.top)
        }
        .padding()
        .onAppear {
            store.send(.recentProjectsSelection(.onAppear))
        }
    }
}

#Preview {
    DirectoryModalView(store: Store(initialState: DirectoryModalFeature.State(
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
        DirectoryModalFeature()
    })
}
