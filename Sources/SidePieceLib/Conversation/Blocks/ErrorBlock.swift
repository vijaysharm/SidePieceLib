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
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.system(size: 20))

            VStack(alignment: .leading, spacing: 4) {
                Text("Error: \(store.error.code)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.red)
                    .textSelection(.enabled)

                Text(store.error.message)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                if let underlying = store.error.underlying {
                    Text(underlying)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                }
            }

            Spacer()
        }
        .padding(12)
        .background(theme.errorBackground)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(theme.errorBorder, lineWidth: 1)
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
