//
//  RecentProjectsClient.swift
//  SidePiece
//

import Dependencies
import DependenciesMacros
import Foundation

@DependencyClient
public struct RecentProjectsClient: Sendable {
    // Core operations
    public var loadAll: @Sendable () async throws -> [RecentProject]
    public var add: @Sendable (URL) async throws -> RecentProject
    public var remove: @Sendable (UUID) async throws -> Void
    public var resolve: @Sendable (RecentProject) async throws -> URL
    
    // Convenience
    public var clear: @Sendable () async throws -> Void
}

extension RecentProjectsClient {
    public init(key recent: StorageKey<[RecentProject]>) {
        @Dependency(\.uuid) var uuid
        @Dependency(\.date) var date
        self.init(
            loadAll: {
                try recent.read()
            },
            add: { url in
                let didStartAccessing = url.startAccessingSecurityScopedResource()
                defer { if didStartAccessing { url.stopAccessingSecurityScopedResource() } }

                let bookmarkData = try url.bookmarkData(
                    options: [.withSecurityScope],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                
                let project = RecentProject(
                    id: uuid(),
                    url: url,
                    bookmarkData: bookmarkData,
                    lastAccessed: date()
                )
                                
                // Load existing, prepend new, limit to 20
                var projects: [RecentProject] = []
                if let current = try? recent.read() {
                    projects.append(contentsOf: current)
                }
                projects.removeAll { $0.pathString == project.pathString }
                projects.insert(project, at: 0)
                projects = Array(projects.prefix(20))
              
                try recent.write(projects)
                
                return project
            },
            remove: { id in
                var projects = try recent.read()
                projects.removeAll { $0.id == id }
                try recent.write(projects)
            },
            resolve: { project in
                var isStale = false
                let url = try URL(
                    resolvingBookmarkData: project.bookmarkData,
                    options: [.withSecurityScope],
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )
                
                if isStale {
                    let didStartAccessing = url.startAccessingSecurityScopedResource()
                    defer { if didStartAccessing { url.stopAccessingSecurityScopedResource() } }
                    let bookmarkData = try url.bookmarkData(
                        options: [.withSecurityScope],
                        includingResourceValuesForKeys: nil,
                        relativeTo: nil
                    )
                    let project = RecentProject(
                        id: project.id,
                        url: url,
                        bookmarkData: bookmarkData,
                        lastAccessed: date()
                    )
                    
                    var projects = try recent.read()
                    projects.removeAll { $0.id == project.id }
                    projects.insert(project, at: 0)
                    projects = Array(projects.prefix(20))
                    try recent.write(projects)
                }
                
                return url
            },
            clear: {
                try recent.write([])
            }
        )
    }
}

extension StorageKey where T == [RecentProject] {
    static var memory: Self {
        StorageKey(
            id: "com.sidepiece.recentProjects",
        ) { id in
            @Dependency(\.inMemoryClient) var client
            guard let data = try client.read(id) else {
                throw StorageKeyError.dataNotFound
            }
            
            @Dependency(\.jsonCoder) var coder
            return try coder.decode([RecentProject].self, from: data)
        } write: { id, list in
            @Dependency(\.jsonCoder) var coder
            let data = try coder.encode(list)
            
            @Dependency(\.inMemoryClient) var client
            try client.save(id, data)
        }
    }
}

extension RecentProjectsClient: DependencyKey {
    public static let liveValue = RecentProjectsClient(key: .memory)
    
    public static let testValue = RecentProjectsClient(
        loadAll: { [] },
        add: { _ in throw NSError(domain: "", code: 0) },
        remove: { _ in },
        resolve: { _ in throw NSError(domain: "", code: 0) },
        clear: {}
    )
}

extension DependencyValues {
    public var recentProjectsClient: RecentProjectsClient {
        get { self[RecentProjectsClient.self] }
        set { self[RecentProjectsClient.self] = newValue }
    }
}
