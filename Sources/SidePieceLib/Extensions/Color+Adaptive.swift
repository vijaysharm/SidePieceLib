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
    public init(light: Color, dark: Color) {
        self.init(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark ? NSColor(dark) : NSColor(light)
        }))
    }
}
#endif

// MARK: - Hex Color Helper

public extension Color {
    public init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
