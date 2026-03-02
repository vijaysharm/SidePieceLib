//
//  AttachmentModel.swift
//  SidePiece
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers

public struct AttachmentModel: Sendable, Equatable, Identifiable {
    public enum ModelType: Sendable, Equatable {
        case file(URL, UTType)
        case tool(String, Image)

        var title: String {
            switch self {
            case let .file(url, _):
                url.lastPathComponent
            case let .tool(name, _):
                name
            }
        }

        var image: Image {
            switch self {
            case let .file(_, type):
                type.icon
            case let .tool(_, image):
                image
            }
        }
    }

    public let id: UUID
    public let type: ModelType
}
