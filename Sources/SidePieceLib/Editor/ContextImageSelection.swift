//
//  ContextImageSelection.swift
//  SidePiece
//

import ComposableArchitecture
import SwiftUI
import UniformTypeIdentifiers

@Reducer
struct ContextImageSelectionFeature {
    @ObservableState
    struct State: Equatable {
        var presentImagePicker = false
        var files: [ManagedFile] = []
    }

    enum Action: Equatable {
        case presentImagePickerChanged(Bool)
        case `internal`(InternalAction)
        case delegate(DelegateAction)

        @CasePathable
        enum InternalAction: Equatable {
            case removeImage(ManagedFile)
            case imageSelected([URL])
            case imagesStored([ManagedFile])
            case storageError(String)
        }

        @CasePathable
        enum DelegateAction: Equatable {
            case viewImage(URL)
        }
    }

    @Dependency(\.fileStorageClient) var fileStorageClient

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .presentImagePickerChanged(value):
                state.presentImagePicker = value
                return .none
            case let .internal(.removeImage(file)):
                state.files.removeAll { $0.id == file.id }
                return .run { _ in
                    try await fileStorageClient.removeFile(file.id)
                }
            case let .internal(.imageSelected(urls)):
                return .run { send in
                    var storedFiles: [ManagedFile] = []
                    for url in urls {
                        do {
                            let file = try await fileStorageClient.addFile(url)
                            storedFiles.append(file)
                        } catch {
                            await send(.internal(.storageError(error.localizedDescription)))
                        }
                    }
                    await send(.internal(.imagesStored(storedFiles)))
                }
            case let .internal(.imagesStored(files)):
                for file in files {
                    if !state.files.contains(where: { $0.id == file.id }) {
                        state.files.append(file)
                    }
                }
                return .none
            case .internal(.storageError):
                return .none
            case .delegate:
                return .none
            }
        }
    }
}

struct ContextImageSelectionView: View {
    @Bindable var store: StoreOf<ContextImageSelectionFeature>
    @Dependency(\.fileStorageClient) var fileStorageClient

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(store.files) { file in
                    ContextImageThumbnailView(
                        store: store,
                        file: file,
                        url: fileStorageClient.getFileURL(file)
                    )
                }
            }
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fileImporter(
            isPresented: $store.presentImagePicker.sending(\.presentImagePickerChanged),
            allowedContentTypes: UTType.supportedImageTypes,
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case let .success(urls):
                store.send(.internal(.imageSelected(urls)))
            case .failure:
                break
            }
        }
    }
}

private struct ContextImageThumbnailView: View {
    let store: StoreOf<ContextImageSelectionFeature>
    let file: ManagedFile
    let url: URL

    @State private var isHovered = false

    var body: some View {
        Button {
            store.send(.delegate(.viewImage(url)))
        } label: {
            AsyncImage(url: url) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Color.gray.opacity(0.3)
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            if isHovered {
                Button {
                    store.send(.internal(.removeImage(file)))
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.black.opacity(0.6))
                }
                .buttonStyle(.plain)
                .offset(x: 4, y: -4)
            }
        }
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

extension ContextImageSelectionFeature.State {
    var content: [ContentPart] {
        files.map {
            if $0.contentType.isImageType {
                .image(FileSource(url: $0.url, contentType: $0.contentType))
            } else {
                .file(FileSource(url: $0.url, contentType: $0.contentType))
            }
        }
    }
}

#Preview {
    SidePieceView()
        .frame(width: 900, height: 500)
}
