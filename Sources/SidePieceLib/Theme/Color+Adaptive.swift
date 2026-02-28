//
//  Color+Adaptive.swift
//  SidePiece
//

import SwiftUI

#if os(macOS)
import AppKit

extension Color {
    /// Creates a color that automatically adapts between light and dark appearance.
    /// Uses `NSColor(name:dynamicProvider:)` so the color resolves at render time
    /// without needing per-view `@Environment(\.colorScheme)` checks.
    init(light: Color, dark: Color) {
        self.init(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark ? NSColor(dark) : NSColor(light)
        }))
    }
}
#endif
