//
//  FileStorageClient.swift
//  SidePiece
//

import Dependencies
import DependenciesMacros
import Foundation
import UniformTypeIdentifiers

public struct ManagedFile: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let originalFilename: String
    public let storedFilename: String
    public let dateAdded: Date
    public let fileSize: Int64
    public let contentType: UTType
    public let url: URL
}

public enum FileType: String, Codable, Sendable, CaseIterable {
    case image
    case document
    case sourceCode
    case other

    var subdirectory: String {
        switch self {
        case .image: "images"
        case .sourceCode: "source_code"
        case .document: "documents"
        case .other: "other"
        }
    }
}

struct FileStorageManifest: Codable, Sendable {
    var version: Int = 1
    var files: [UUID: ManagedFile] = [:]
}

public enum FileStorageError: LocalizedError, Equatable {
    // Directory operations
    case directoryCreationFailed(path: String, reason: FileSystemReason)

    // File operations
    case sourceFileNotFound(path: String)
    case sourceFileNotReadable(path: String, reason: FileSystemReason)
    case copyFailed(source: String, destination: String, reason: FileSystemReason)
    case deleteFailed(path: String, reason: FileSystemReason)
    case fileAlreadyExists(path: String)

    // Manifest operations
    case manifestDecodingFailed(reason: JSONCoderClient.DecodingFailedError)
    case manifestEncodingFailed(reason: JSONCoderClient.EncodingFailedError)
    case manifestWriteFailed(reason: FileSystemReason)

    // Logical errors
    case fileNotManaged(id: UUID)

    public var errorDescription: String? {
        switch self {
        case let .directoryCreationFailed(path, reason):
            "Failed to create directory at \(path): \(reason.localizedDescription)"
        case let .sourceFileNotFound(path):
            "Source file not found at \(path)"
        case let .sourceFileNotReadable(path, reason):
            "Cannot read source file at \(path): \(reason.localizedDescription)"
        case let .copyFailed(source, _, reason):
            "Failed to copy file \(source): \(reason.localizedDescription)"
        case let .deleteFailed(path, reason):
            "Failed to delete file at \(path): \(reason.localizedDescription)"
        case let .fileAlreadyExists(path):
            "File already exists at \(path)"
        case let .manifestDecodingFailed(reason):
            "Failed to read file manifest: \(reason.localizedDescription)"
        case let .manifestEncodingFailed(reason):
            "Failed to save file manifest: \(reason.localizedDescription)"
        case let .manifestWriteFailed(reason):
            "Failed to write file manifest: \(reason.localizedDescription)"
        case let .fileNotManaged(id):
            "No managed file found with id \(id)"
        }
    }

    public enum FileSystemReason: Equatable, Sendable {
        case permissionDenied
        case diskFull
        case fileNotFound
        case fileExists
        case invalidPath
        case readOnlyFileSystem
        case ioError
        case unknown(code: Int, domain: String)

        init(from error: Error) {
            let nsError = error as NSError
            switch (nsError.domain, nsError.code) {
            case (NSCocoaErrorDomain, NSFileNoSuchFileError),
                 (NSCocoaErrorDomain, NSFileReadNoSuchFileError),
                 (NSPOSIXErrorDomain, 2): // ENOENT
                self = .fileNotFound
            case (NSCocoaErrorDomain, NSFileWriteOutOfSpaceError),
                 (NSPOSIXErrorDomain, 28): // ENOSPC
                self = .diskFull
            case (NSCocoaErrorDomain, NSFileWriteNoPermissionError),
                 (NSCocoaErrorDomain, NSFileReadNoPermissionError),
                 (NSPOSIXErrorDomain, 13): // EACCES
                self = .permissionDenied
            case (NSCocoaErrorDomain, NSFileWriteFileExistsError):
                self = .fileExists
            case (NSCocoaErrorDomain, NSFileWriteInvalidFileNameError),
                 (NSCocoaErrorDomain, NSFileReadInvalidFileNameError):
                self = .invalidPath
            case (NSPOSIXErrorDomain, 30): // EROFS
                self = .readOnlyFileSystem
            case (NSPOSIXErrorDomain, 5): // EIO
                self = .ioError
            default:
                self = .unknown(code: nsError.code, domain: nsError.domain)
            }
        }

        var localizedDescription: String {
            switch self {
            case .permissionDenied: "permission denied"
            case .diskFull: "disk is full"
            case .fileNotFound: "file not found"
            case .fileExists: "file already exists"
            case .invalidPath: "invalid path"
            case .readOnlyFileSystem: "read-only file system"
            case .ioError: "I/O error"
            case let .unknown(code, domain): "unknown error (\(domain):\(code))"
            }
        }
    }
}

@DependencyClient
public struct FileStorageClient: Sendable {
    public var addFile: @Sendable (URL) async throws -> ManagedFile
    public var removeFile: @Sendable (UUID) async throws -> Void
    public var getFileURL: @Sendable (ManagedFile) -> URL = { _ in URL(fileURLWithPath: "/") }
    public var listFiles: @Sendable (FileType?) async throws -> [ManagedFile]
    public var getFile: @Sendable (UUID) async throws -> ManagedFile?
}

private enum FileStorageHelpers {
    static var baseDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let bundleId = Bundle.main.bundleIdentifier ?? ""
        return appSupport.appendingPathComponent(bundleId).appendingPathComponent("ManagedFiles")
    }

    static var manifestURL: URL {
        baseDirectory.appendingPathComponent("manifest.json")
    }

    static func ensureDirectoryStructure() throws(FileStorageError) {
        let fileManager = FileManager.default
        for fileType in FileType.allCases {
            let dir = baseDirectory.appendingPathComponent(fileType.subdirectory)
            if !fileManager.fileExists(atPath: dir.path) {
                do {
                    try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
                } catch {
                    throw .directoryCreationFailed(
                        path: dir.path,
                        reason: .init(from: error)
                    )
                }
            }
        }
    }

    static func loadManifest() throws(FileStorageError) -> FileStorageManifest {
        guard let data = FileManager.default.contents(atPath: manifestURL.path) else {
            return FileStorageManifest()
        }
        
        do {
            @Dependency(\.jsonCoder) var coder
            return try coder.decode(FileStorageManifest.self, from: data)
        } catch {
            throw .manifestDecodingFailed(reason: error)
        }
    }

    static func saveManifest(_ manifest: FileStorageManifest) throws(FileStorageError) {
        let data: Data
        do {
            @Dependency(\.jsonCoder) var coder
            data = try coder.encode(manifest)
        } catch {
            throw .manifestEncodingFailed(reason: error)
        }

        do {
            try data.write(to: manifestURL, options: .atomic)
        } catch {
            throw .manifestWriteFailed(reason: .init(from: error))
        }
    }

    static func fileURL(for file: ManagedFile) -> URL {
        baseDirectory
            .appendingPathComponent(file.contentType.fileType.subdirectory)
            .appendingPathComponent(file.storedFilename)
    }

    static func copyFile(from source: URL, to destination: URL) throws(FileStorageError) {
        do {
            try FileManager.default.copyItem(at: source, to: destination)
        } catch {
            let reason = FileStorageError.FileSystemReason(from: error)
            if reason == .fileExists {
                throw .fileAlreadyExists(path: destination.path)
            }
            throw .copyFailed(source: source.path, destination: destination.path, reason: reason)
        }
    }

    static func deleteFile(at url: URL) throws(FileStorageError) {
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            throw .deleteFailed(path: url.path, reason: .init(from: error))
        }
    }

    static func fileAttributes(at url: URL) throws(FileStorageError) -> [FileAttributeKey: Any] {
        do {
            return try FileManager.default.attributesOfItem(atPath: url.path)
        } catch {
            let reason = FileStorageError.FileSystemReason(from: error)
            if reason == .fileNotFound {
                throw .sourceFileNotFound(path: url.path)
            }
            throw .sourceFileNotReadable(path: url.path, reason: reason)
        }
    }
}

extension FileStorageClient: DependencyKey {
    public static let liveValue = {
        @Dependency(\.uuid) var uuid
        @Dependency(\.date) var date

        return FileStorageClient(
            addFile: { sourceURL in
                try FileStorageHelpers.ensureDirectoryStructure()

                let didStartAccessing = sourceURL.startAccessingSecurityScopedResource()
                defer { if didStartAccessing { sourceURL.stopAccessingSecurityScopedResource() } }

                let originalFilename = sourceURL.lastPathComponent
                
                let type = UTType(filenameExtension: sourceURL.pathExtension) ?? .plainText
                let fileId = uuid()

                let storedFilename = "\(fileId.uuidString)-\(originalFilename)"

                let attributes = try FileStorageHelpers.fileAttributes(at: sourceURL)
                let fileSize = (attributes[.size] as? Int64) ?? 0

                let destinationURL = FileStorageHelpers.baseDirectory
                    .appendingPathComponent(type.fileType.subdirectory)
                    .appendingPathComponent(storedFilename)

                try FileStorageHelpers.copyFile(from: sourceURL, to: destinationURL)

                let managedFile = ManagedFile(
                    id: fileId,
                    originalFilename: originalFilename,
                    storedFilename: storedFilename,
                    dateAdded: date(),
                    fileSize: fileSize,
                    contentType: type,
                    url: destinationURL
                )

                var manifest = try FileStorageHelpers.loadManifest()
                manifest.files[fileId] = managedFile
                try FileStorageHelpers.saveManifest(manifest)

                return managedFile
            },
            removeFile: { id in
                var manifest = try FileStorageHelpers.loadManifest()
                guard let file = manifest.files[id] else { return }

                let fileURL = FileStorageHelpers.fileURL(for: file)
                try? FileStorageHelpers.deleteFile(at: fileURL)

                manifest.files.removeValue(forKey: id)
                try FileStorageHelpers.saveManifest(manifest)
            },
            getFileURL: { file in
                FileStorageHelpers.fileURL(for: file)
            },
            listFiles: { filterType in
                let manifest = try FileStorageHelpers.loadManifest()
                let files = Array(manifest.files.values)
                if let filterType {
                    return files.filter { $0.contentType.fileType == filterType }
                }
                return files
            },
            getFile: { id in
                try FileStorageHelpers.loadManifest().files[id]
            }
        )
    }()

    public static let testValue = FileStorageClient()
}

extension DependencyValues {
    public var fileStorageClient: FileStorageClient {
        get { self[FileStorageClient.self] }
        set { self[FileStorageClient.self] = newValue }
    }
}
