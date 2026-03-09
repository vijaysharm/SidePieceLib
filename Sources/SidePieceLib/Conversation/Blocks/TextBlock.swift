//
//  TextBlock.swift
//  SidePiece
//

import ComposableArchitecture
import SwiftUI
import Textual

@Reducer
public struct TextBlockFeature: Sendable {
    @ObservableState
    public struct State: Identifiable, Equatable, Sendable {
        public let id: UUID
        var content: String
        var isStreaming: Bool
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

struct TextBlockView: View {
    @Bindable var store: StoreOf<TextBlockFeature>
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 0) {
            StructuredText(markdown: store.content)
                .textSelection(.enabled)
                .multilineTextAlignment(.leading)
                .font(theme.typography.body)
                .foregroundStyle(.primary)
                .lineSpacing(4)

            if store.isStreaming {
                BlinkingCursor()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

fileprivate struct BlinkingCursor: View {
    @State private var isVisible = true

    var body: some View {
        Rectangle()
            .fill(Color.primary)
            .frame(width: 2, height: 16)
            .opacity(isVisible ? 1 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                    isVisible.toggle()
                }
            }
    }
}

#Preview {
    ScrollView {
        VStack {
            TextBlockView(store: Store(initialState: TextBlockFeature.State(
                id: UUID(),
                content: "Hello, this is some streaming text...",
                isStreaming: true
            )) {
                TextBlockFeature()
            })
            TextBlockView(store: Store(initialState: TextBlockFeature.State(
                id: UUID(),
                content: "Hello, this is complete text.",
                isStreaming: false
            )) {
                TextBlockFeature()
            })
        }
    }
    .padding()
}
