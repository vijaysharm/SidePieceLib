//
//  ErrorBlock.swift
//  SidePiece
//

import ComposableArchitecture
import SwiftUI

@Reducer
public struct ErrorBlockFeature: Sendable {
    @ObservableState
    public struct State: Identifiable, Equatable, Sendable {
        public let id: UUID
        let error: LLMError
    }
    
    public enum Action: Equatable, Sendable {
        @CasePathable
        public enum DelegateAction: Equatable, Sendable {}

        @CasePathable
        public enum InternalAction: Equatable, Sendable {}

        case `internal`(InternalAction)
        case delegate(DelegateAction)
    }
    
    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            default:
                return .none
            }
        }
    }
}

struct ErrorBlockView: View {
    @Bindable var store: StoreOf<ErrorBlockFeature>
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: theme.spacing.lg) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(theme.colors.statusError)
                .font(theme.typography.alertIcon)

            VStack(alignment: .leading, spacing: theme.spacing.xs) {
                Text("Error: \(store.error.code)")
                    .font(theme.typography.label)
                    .fontWeight(.semibold)
                    .foregroundStyle(theme.colors.statusError)
                    .textSelection(.enabled)

                Text(store.error.message)
                    .font(theme.typography.bodySmall)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                if let underlying = store.error.underlying {
                    Text(underlying)
                        .font(theme.typography.monoSmall)
                        .foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                }
            }

            Spacer()
        }
        .padding(theme.spacing.lg)
        .background(theme.colors.statusErrorBackground)
        .cornerRadius(theme.radius.md)
        .overlay(
            RoundedRectangle(cornerRadius: theme.radius.md)
                .stroke(theme.colors.statusErrorBorder, lineWidth: theme.borderWidth.thin)
        )
    }
}

#Preview {
    ErrorBlockView(store: Store(initialState: ErrorBlockFeature.State(
        id: UUID(),
        error: LLMError(code: "rate_limit", message: "Too many requests", underlying: "Please wait before retrying")
    )) {
        ErrorBlockFeature()
    })
    .padding()
}
