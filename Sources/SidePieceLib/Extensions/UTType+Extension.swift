//
//  UTType+Extension.swift
//  SidePiece
//

import UniformTypeIdentifiers
import SwiftUI

public extension UTType {
    /// Supported image UTTypes for file picker and type detection
    /// These types are also inline with what's supported by AsyncImage
    /// Think carefully if this is changed as it affects what can and can't be displayed
    /// in the Image selection view
    static let supportedImageTypes: [UTType] = [
        .jpeg, .png, .gif, .heic, .heif, .webP, .tiff, .bmp
    ]
    
    var icon: Image {
        // Swift source code
        if conforms(to: .swiftSource) {
            return Image(systemName: "swift")
        }
        
        // Images
        if conforms(to: .image) {
            return Image(systemName: "photo")
        }
        
        // PDF
        if conforms(to: .pdf) {
            return Image(systemName: "doc.fill")
        }
        
        // Archives
        if conforms(to: .archive) || conforms(to: .zip) {
            return Image(systemName: "doc.zipper")
        }
        
        // Source code
        if conforms(to: .sourceCode) {
            // Check specific programming languages
            if let ext = preferredFilenameExtension {
                switch ext.lowercased() {
                case "js", "jsx", "ts", "tsx":
                    return Image(systemName: "curlybraces")
                case "py":
                    return Image(systemName: "chevron.left.forwardslash.chevron.right")
                case "c", "h":
                    return Image(systemName: "c.square")
                case "cpp", "hpp", "cc", "cxx":
                    return Image(systemName: "cplusplus")
                case "rb":
                    return Image(systemName: "diamond")
                case "go":
                    return Image(systemName: "g.square")
                case "rs":
                    return Image(systemName: "r.square")
                case "java", "kt", "kts":
                    return Image(systemName: "cup.and.saucer")
                default:
                    break
                }
            }
            return Image(systemName: "chevron.left.forwardslash.chevron.right")
        }
        
        // JSON
        if conforms(to: .json) {
            return Image(systemName: "curlybraces.square")
        }
        
        // XML and property lists
        if conforms(to: .xml) || conforms(to: .propertyList) {
            return Image(systemName: "gearshape")
        }
        
        // HTML
        if conforms(to: .html) {
            return Image(systemName: "globe")
        }
        
        // Plain text
        if conforms(to: .plainText) {
            return Image(systemName: "doc.text")
        }
        
        // Check by file extension for types not well-represented in UTType
        if let ext = preferredFilenameExtension?.lowercased() {
            switch ext {
            case "md", "markdown":
                return Image(systemName: "doc.richtext")
            case "css", "scss", "sass", "less":
                return Image(systemName: "paintbrush")
            case "yaml", "yml", "toml":
                return Image(systemName: "gearshape")
            case "sh", "bash", "zsh":
                return Image(systemName: "terminal")
            case "sql":
                return Image(systemName: "cylinder")
            default:
                break
            }
        }
        
        // Default to generic document icon
        return Image(systemName: "doc")
    }
    
    var fileType: FileType {
        if Self.supportedImageTypes.contains(where: { conforms(to: $0) }) {
            .image
        } else if conforms(to: .text) {
            .sourceCode
        } else if conforms(to: .compositeContent) {
            .document
        } else {
            .other
        }
    }
    
    var isImageType: Bool {
        UTType.supportedImageTypes.contains(where: { conforms(to: $0) })
    }
}
