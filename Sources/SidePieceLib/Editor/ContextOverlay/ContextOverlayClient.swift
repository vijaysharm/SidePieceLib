//
//  ContextOverlayClient.swift
//  SidePiece
//

import Dependencies
import DependenciesMacros
import Foundation
import SwiftUI
import UniformTypeIdentifiers

@DependencyClient
public struct ContextOverlayClient: Sendable {
    public var actions: @Sendable (URL) async -> [ContextItem] = { _ in [] }
    public var search: @Sendable (URL, String, UInt) async -> [ContextItem] = { _, _, _ in [] }
}

extension ContextOverlayClient: DependencyKey {
    public static let liveValue = {
        @Dependency(\.projectIndexerClient) var projectIndexerClient
        let indexer = projectIndexerClient.indexer()
        return ContextOverlayClient(
            actions: { url in
                let entries = await indexer.top(3, from: url)
                let deep = await indexer.top(10, from: url)
                return entries.enumerated().compactMap {
                    .from(entry: $1, source: url, underline: entries.count == $0 + 1)
                } + [
                    .container(ContextItem.ContainerData(
                        id: UUID(),
                        icon: Image(systemName: "document.on.document"),
                        title: "Files & Folders",
                        items: deep.compactMap {
                            .from(entry: $0, source: url)
                        }
                    )),
//                    .item(ContextItem.ItemData(
//                        id: UUID(),
//                        type: .tool,
//                        icon: Image(systemName: "globe"),
//                        title: "Browser",
//                        subtitle: nil,
//                        sectionTitle: nil,
//                        underline: false
//                    )),
                ]
            },
            search: { url, term, limit in
                let results = await indexer.search(term, from: url, limit: limit)
                return results.compactMap { .from(entry: $0, source: url) }
            }
        )
    }()
}

private extension ContextItem {
    static func from(
        entry: ProjectIndexer.Entry,
        source url: URL,
        underline: Bool = false
    ) -> Self {
        let path = url.appendingPathComponent(entry.relative, conformingTo: entry.contentType)
        return .item(ContextItem.ItemData(
            id: entry.id,
            type: .file(path, entry.contentType),
            icon: entry.contentType.icon,
            title: path.lastPathComponent,
            subtitle: url.appending(component: entry.relative).deletingLastPathComponent().path(),
            sectionTitle: nil,
            underline: underline
        ))
    }
}

extension DependencyValues {
    public var contextOverlayClient: ContextOverlayClient {
        get { self[ContextOverlayClient.self] }
        set { self[ContextOverlayClient.self] = newValue }
    }
}

