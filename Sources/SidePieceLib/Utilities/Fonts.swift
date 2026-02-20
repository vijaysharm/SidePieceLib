//
//  Fonts.swift
//  SidePiece
//

#if os(macOS)
import AppKit
typealias AppFont = NSFont
#elseif os(iOS)
import UIKit
typealias AppFont = UIFont
#endif

extension AppFont {
    static func monoSpacedFont(
        size: CGFloat = 16,
        scale: CGFloat = 1
    ) -> AppFont { .monospacedSystemFont(ofSize: size * scale, weight: .regular) }
}

extension AppFont {
    var minHeight: CGFloat {
        Double(ascender + abs(descender) + leading)
    }
    
    var lineHeight: CGFloat {
        ceil(ascender - descender + leading)
    }
}
