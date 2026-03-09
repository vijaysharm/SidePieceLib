//
//  ImageOverlay.swift
//  SidePiece
//

import ComposableArchitecture
import SwiftUI

@Reducer
public struct ImageOverlayFeature: Sendable {
    @ObservableState
    public struct State: Equatable {
        let url: URL
    }

    public enum Action: Equatable {
        case dismiss
    }

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .dismiss:
                return .none
            }
        }
    }
}

struct ImageOverlayView: View {
    let store: StoreOf<ImageOverlayFeature>
    @Environment(\.theme) private var theme

    var body: some View {
        ZStack {
            theme.colors.scrim
                .contentShape(Rectangle())
                .onTapGesture {
                    store.send(.dismiss)
                }
                .transition(.opacity)

            AsyncImage(url: store.url) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } placeholder: {
                ProgressView()
                    .controlSize(.large)
            }
            .padding(theme.spacing.xxxl)
            .allowsHitTesting(false)
            .transition(.opacity.combined(with: .offset(y: -8)))

            VStack {
                HStack {
                    Spacer()
                    Button {
                        store.send(.dismiss)
                    } label: {
                        Image(systemName: "xmark")
                            .font(theme.typography.label)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(
                                Circle()
                                    .fill(theme.colors.border)
                            )
                    }
                    .buttonStyle(.plain)
                    .padding(theme.spacing.xl)
                }
                Spacer()
            }
        }
    }
}
