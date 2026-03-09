//
//  DeleteConfirmation.swift
//  SidePiece

import ComposableArchitecture
import SwiftUI

@Reducer
public struct DeleteConfirmationFeature: Sendable {
    @ObservableState
    public struct State: Equatable {
        public enum Kind: Equatable {
            case conversation(id: UUID, title: String)
            case project(id: UUID, title: String, url: URL)
        }
        let kind: Kind

        var title: String {
            switch kind {
            case .conversation: "Delete Conversation?"
            case .project: "Remove Project?"
            }
        }

        var message: String {
            switch kind {
            case let .conversation(_, title):
                "\u{201C}\(title)\u{201D} will be permanently deleted."
            case let .project(_, title, _):
                "\u{201C}\(title)\u{201D} and all its conversations will be permanently removed."
            }
        }

        var confirmButtonTitle: String {
            switch kind {
            case .conversation: "Delete"
            case .project: "Remove"
            }
        }
    }

    public enum Action: Equatable {
        case cancel
        case delegate(DelegateAction)

        @CasePathable
        public enum DelegateAction: Equatable {
            case confirmDeleteConversation(UUID)
            case confirmRemoveProject(id: UUID, url: URL)
        }
    }

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .cancel:
                return .none
            case .delegate:
                return .none
            }
        }
    }
}

struct DeleteConfirmationView: View {
    let store: StoreOf<DeleteConfirmationFeature>
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: theme.spacing.xl) {
            Text(store.title)
                .font(theme.typography.heading)
                .fontWeight(.semibold)

            Text(store.message)
                .font(theme.typography.bodySmall)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: theme.spacing.lg) {
                Button {
                    store.send(.cancel)
                } label: {
                    Text("Cancel")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, theme.spacing.md)
                }
                .buttonStyle(.plain)
                .background(
                    RoundedRectangle(cornerRadius: theme.radius.md)
                        .stroke(theme.colors.border, lineWidth: theme.borderWidth.thin)
                )

                Button(role: .destructive) {
                    switch store.kind {
                    case let .conversation(id, _):
                        store.send(.delegate(.confirmDeleteConversation(id)))
                    case let .project(id, _, url):
                        store.send(.delegate(.confirmRemoveProject(id: id, url: url)))
                    }
                } label: {
                    Text(store.confirmButtonTitle)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, theme.spacing.md)
                }
                .buttonStyle(.plain)
                .background(
                    RoundedRectangle(cornerRadius: theme.radius.md)
                        .fill(theme.colors.statusError)
                )
            }
        }
        .padding(theme.spacing.xxl)
        .background(theme.colors.backgroundOverlay)
        .clipShape(RoundedRectangle(cornerRadius: theme.radius.lg))
    }
}
