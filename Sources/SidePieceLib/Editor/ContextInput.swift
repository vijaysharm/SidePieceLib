//
//  ContextInput.swift
//  SidePiece
//

import ComposableArchitecture
import SwiftUI
import UniformTypeIdentifiers

@Reducer
public struct ContextInputFeature: Sendable {
    @ObservableState
    public struct State: Equatable, Identifiable {
        public enum ToolBarMode: Sendable, Equatable {
            case expandOnFocus
            case alwaysShow
        }
        public var id: UUID = UUID()
        var frame: CGRect = .zero
        var inputField: TextInputFeature.State
        var images: ContextImageSelectionFeature.State
        var agentToolbar: ContextAgentToolbarFeature.State
        var toolbarMode = ToolBarMode.alwaysShow
        var isDragOver: Bool = false
    }
    
    public enum Action: Equatable {
        @CasePathable
        public enum InternalAction: Equatable {
            case frameDidChange(CGRect)
            case addImage
            case setDragOver(Bool)
            case filesDropped([URL])
            case filesStored([ManagedFile])
            case dropError(String)
        }
        
        @CasePathable
        public enum DelegateAction: Equatable {
            case frameDidChange(CGRect)
            case submit
            case contextOverlay
            case stopStreaming
            case viewImage(URL)
        }
        
        case inputField(TextInputFeature.Action)
        case images(ContextImageSelectionFeature.Action)
        case agentToolbar(ContextAgentToolbarFeature.Action)
        case delegate(DelegateAction)
        case `internal`(InternalAction)
    }
    
    @Dependency(\.fileStorageClient) var fileStorageClient

    public var body: some ReducerOf<Self> {
        Scope(state: \.inputField, action: \.inputField) {
            TextInputFeature()
        }
        Scope(state: \.images, action: \.images) {
            ContextImageSelectionFeature()
        }
        Scope(state: \.agentToolbar, action: \.agentToolbar) {
            ContextAgentToolbarFeature()
        }
        Reduce { state, action in
            switch action {
            case let .images(.delegate(.viewImage(url))):
                return .send(.delegate(.viewImage(url)))
            case .images:
                return .none
            case .inputField:
                return .none
            case .internal(.addImage):
                state.images.presentImagePicker = true
                return .none
            case let .internal(.frameDidChange(frame)):
                state.frame = frame
                return .send(.delegate(.frameDidChange(frame)))
            case let .internal(.setDragOver(isDragOver)):
                state.isDragOver = isDragOver
                return .none
            case let .internal(.filesDropped(urls)):
                return .run { send in
                    var storedFiles: [ManagedFile] = []
                    for url in urls {
                        do {
                            let file = try await fileStorageClient.addFile(url)
                            storedFiles.append(file)
                        } catch {
                            await send(.internal(.dropError(error.localizedDescription)))
                        }
                    }
                    if !storedFiles.isEmpty {
                        await send(.internal(.filesStored(storedFiles)))
                    }
                }
            case let .internal(.filesStored(files)):
                let images = files.filter { $0.contentType.isImageType }
                let nonImages = files.filter { !$0.contentType.isImageType }

                for file in images {
                    if !state.images.files.contains(where: { $0.id == file.id }) {
                        state.images.files.append(file)
                    }
                }

                for file in nonImages {
                    state.inputField.attach(
                        VSInlineAttachment.VSAttachmentModel(
                            id: file.id,
                            type: .file(file.url, file.contentType)
                        )
                    )
                }
                return .none
            case .agentToolbar:
                return .none
            case .internal(.dropError):
                return .none
            case .delegate:
                return .none
            }
        }
    }
}

private extension Store where State == ContextInputFeature.State, Action == ContextInputFeature.Action {
    var showBottomBar: Bool {
        switch state.toolbarMode {
        case .alwaysShow:
            return true
        case .expandOnFocus:
            return state.inputField.isFocused
        }
    }
}

struct ContextInputView: View {
    @Bindable var store: StoreOf<ContextInputFeature>
    var isStreaming: Bool = false
    var tokenUsage: TokenUsage
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            ContextImageSelectionView(
                store: store.scope(
                    state: \.images,
                    action: \.images
                )
            )
            .padding(.bottom, store.images.files.isEmpty ? 0 : 12)
            
            TextInputViewRepresentable(
                store: store.scope(
                    state: \.inputField,
                    action: \.inputField
                )
            )
            .frame(height: store.inputField.height)
            if store.showBottomBar {
                HStack(spacing: 12) {
                    ContextAgentToolbarView(
                        store: store.scope(
                            state: \.agentToolbar,
                            action: \.agentToolbar
                        )
                    )
                    
                    Spacer()
                    
                    HStack(spacing: 2) {
                        tokenUsageView()
                        bottomBarIconButton(systemName: "photo", action: .internal(.addImage))
                        Button {
                            if isStreaming {
                                store.send(.delegate(.stopStreaming))
                            } else {
                                store.send(.delegate(.submit))
                            }
                        } label: {
                            Group {
                                if isStreaming {
                                    Image(systemName: "stop.fill")
                                } else {
                                    Image(systemName: "arrow.up")
                                }
                            }
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(theme.invertedContent)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(
                                store.agentToolbar.selectedAgent.color
                            ))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 24)
            }
        }
        .padding(12)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color(NSColor.quaternaryLabelColor), lineWidth: 1)
        )
        .overlay {
            if store.isDragOver {
                dropTargetOverlay
            }
        }
        .onDrop(
            of: [.fileURL],
            isTargeted: $store.isDragOver.sending(\.internal.setDragOver)
        ) { providers in
            guard !providers.isEmpty else { return false }
            
            Task {
                var urls: [URL] = []
                for provider in providers {
                    guard let url = try? await provider.load(type: URL.self) else { continue }
                    urls.append(url)
                }
                if !urls.isEmpty {
                    store.send(.internal(.filesDropped(urls)))
                }
            }
            return true
        }
        .onGeometryChange(for: CGRect.self) { geometry in
            geometry.frame(in: .named("conversationView"))
        } action: { newValue in
            store.send(.internal(.frameDidChange(newValue)))
        }
    }
    
    private var dropTargetOverlay: some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(Color.accentColor.opacity(0.1))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.accentColor, lineWidth: 2)
            )
            .overlay {
                VStack(spacing: 8) {
                    Image(systemName: "arrow.down.doc")
                        .font(.system(size: 24))
                    Text("Drop files here")
                        .font(theme.typography.body(weight: .medium))
                }
                .foregroundStyle(Color.accentColor)
            }
    }
    
    private func bottomBarIconButton(
        systemName: String,
        action: ContextInputFeature.Action
    ) -> some View {
        Button {
            store.send(action)
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private func tokenUsageView() -> some View {
        if let contextWindow = store.agentToolbar.selectedModel.contextWindow, contextWindow > 0 {
            let fraction = min(Double(tokenUsage.totalTokens) / Double(contextWindow), 1.0)
            let tooltip = tokenUsageTooltip(usage: tokenUsage, contextWindow: contextWindow)
            ZStack {
                Circle()
                    .stroke(
                        theme.tokenRingTrack,
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                    )
                    .frame(width: 14, height: 14)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(
                        tokenUsageColor(fraction: fraction),
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 14, height: 14)
            }
            .contentShape(Rectangle())
            .frame(width: 28, height: 28)
            .help(tooltip)
        }
    }

    private func tokenUsageColor(fraction: Double) -> Color {
        if fraction > 0.8 {
            .orange
        } else if fraction > 0.5 {
            .yellow
        } else {
            .secondary
        }
    }

    private func tokenUsageTooltip(usage: TokenUsage, contextWindow: Int) -> String {
        let format: (Int) -> String = { tokens in
            if tokens >= 1000 {
                return "\(tokens / 1000)K"
            }
            return "\(tokens)"
        }
        return "\(format(usage.totalTokens)) / \(format(contextWindow)) tokens"
    }
}

private extension NSItemProvider {
    func load<T>(type: T.Type) async throws -> T? where T : _ObjectiveCBridgeable & Sendable, T._ObjectiveCType : NSItemProviderReading {
        return try await withCheckedThrowingContinuation { continuation in
            _ = loadObject(ofClass: type) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: result)
                }
            }
        }
    }
}
