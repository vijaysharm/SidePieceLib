//
//  Theme.swift
//  SidePiece
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

// MARK: - Typography

public struct ThemeTypography: Equatable, Sendable {

    // MARK: Editor (NSFont-based text input)

    /// Font size for the monospaced editor input.
    /// Used to construct the NSFont passed into TextInputFeature.State.
    public var editorFontSize: CGFloat

    /// Line spacing for the editor input.
    public var editorLineSpacing: CGFloat

    /// Editor text color. Stored as SwiftUI Color; convert via
    /// ``editorNSColor`` when constructing TextInputFeature.State.
    public var editorForegroundColor: Color

    // MARK: Content fonts (SwiftUI)

    /// Heading size — conversation titles, page headings (default 20).
    public var headingSize: CGFloat

    /// Body text size — message content, descriptions (default 13).
    public var bodySize: CGFloat

    /// Code / monospaced display size — tool calls, error details (default 12).
    public var codeSize: CGFloat

    /// Small UI text size — metadata, row labels (default 11).
    public var smallSize: CGFloat

    /// Caption / fine-print size — timestamps, token counts (default 9).
    public var captionSize: CGFloat

    // MARK: Computed helpers – SwiftUI Font

    public func heading(weight: Font.Weight = .bold) -> Font {
        .system(size: headingSize, weight: weight)
    }

    public func body(weight: Font.Weight = .regular) -> Font {
        .system(size: bodySize, weight: weight)
    }

    public func code(weight: Font.Weight = .regular) -> Font {
        .system(size: codeSize, weight: weight, design: .monospaced)
    }

    public func small(weight: Font.Weight = .regular) -> Font {
        .system(size: smallSize, weight: weight)
    }

    public func caption(weight: Font.Weight = .regular) -> Font {
        .system(size: captionSize, weight: weight)
    }

    // MARK: Computed helpers – NSFont (for TextKit / NSTextView)

    #if os(macOS)
    /// Monospaced NSFont for the editor text input.
    public var editorNSFont: NSFont {
        .monospacedSystemFont(ofSize: editorFontSize, weight: .regular)
    }

    /// Editor foreground as NSColor for TextKit use.
    public var editorNSColor: NSColor {
        NSColor(editorForegroundColor)
    }
    #endif
}

public extension ThemeTypography {
    static let `default` = ThemeTypography(
        editorFontSize: 15,
        editorLineSpacing: 4,
        editorForegroundColor: .white,
        headingSize: 20,
        bodySize: 13,
        codeSize: 12,
        smallSize: 11,
        captionSize: 9
    )

    static let light = ThemeTypography(
        editorFontSize: 15,
        editorLineSpacing: 4,
        editorForegroundColor: Color(nsColor: .textColor),
        headingSize: 20,
        bodySize: 13,
        codeSize: 12,
        smallSize: 11,
        captionSize: 9
    )
}

// MARK: - Theme

public struct Theme: Equatable, Sendable {

    // MARK: Overlay / modal backdrops

    /// Full-screen dimming backdrop (image overlay, model selection, delete confirmation)
    public var overlayBackdrop: Color

    // MARK: Surfaces

    /// Primary surface for controls and panels (e.g. model selection, delete dialog)
    public var surfaceBackground: Color
    /// Secondary/text background (e.g. search field fill)
    public var surfaceSecondary: Color
    /// Window background used behind message headers
    public var windowBackground: Color

    // MARK: Interactive state fills

    /// Fill for a selected row / item
    public var selectedFill: Color
    /// Fill for a hovered row / item
    public var hoverFill: Color
    /// Fill for a highlighted button / action row
    public var highlightedFill: Color

    // MARK: Borders & strokes

    /// Default thin border color (search fields, cards, new-agent button)
    public var border: Color
    /// Subtle border for settings cards
    public var borderSubtle: Color

    // MARK: Content / text

    /// Send-button / icon background tint (inverted text sitting on the agent color)
    public var invertedContent: Color

    // MARK: Semantic / status colors

    /// Destructive action fill (delete button)
    public var destructive: Color
    /// Error background tint
    public var errorBackground: Color
    /// Error border stroke
    public var errorBorder: Color

    // MARK: Context overlay

    /// Context overlay background
    public var contextOverlayBackground: Color
    /// Context overlay selection/hover fill
    public var contextOverlaySelection: Color
    /// Context overlay border
    public var contextOverlayBorder: Color

    // MARK: Inline attachment (NSColor counterparts)

    /// Accent color for inline attachment background
    public var attachmentAccent: Color
    /// Accent color opacity for inline attachment fill
    public var attachmentAccentFillOpacity: Double
    /// Accent color opacity for inline attachment border
    public var attachmentAccentBorderOpacity: Double

    // MARK: Feature icons (model selection)

    /// Background capsule for feature icon groups
    public var featureIconCapsule: Color

    // MARK: Category tab bar indicator

    /// Active indicator bar in the tab sidebar
    public var tabIndicator: Color

    // MARK: Token usage ring

    /// Token ring track color
    public var tokenRingTrack: Color

    // MARK: Settings card fill

    /// Fill for settings section cards
    public var settingsCardFill: Color
    /// Stroke for settings section cards
    public var settingsCardStroke: Color

    // MARK: Splash screen

    /// Splash screen action button border
    public var splashBorder: Color

    // MARK: Typography

    /// Typography settings (font sizes and editor font parameters).
    public var typography: ThemeTypography
}

// MARK: - Default Dark Theme

public extension Theme {
    /// The built-in dark theme that matches the original hard-coded colors.
    static let dark = Theme(
        overlayBackdrop: Color.black.opacity(0.85),

        surfaceBackground: Color(nsColor: .controlBackgroundColor),
        surfaceSecondary: Color(nsColor: .textBackgroundColor).opacity(0.5),
        windowBackground: Color(nsColor: .windowBackgroundColor),

        selectedFill: Color.white.opacity(0.1),
        hoverFill: Color.white.opacity(0.05),
        highlightedFill: Color(white: 0.25),

        border: Color.white.opacity(0.15),
        borderSubtle: Color.white.opacity(0.1),

        invertedContent: Color(nsColor: .windowBackgroundColor),

        destructive: Color.red,
        errorBackground: Color.red.opacity(0.1),
        errorBorder: Color.red.opacity(0.3),

        contextOverlayBackground: .black,
        contextOverlaySelection: Color.secondary.opacity(0.3),
        contextOverlayBorder: .gray,

        attachmentAccent: Color(nsColor: .controlAccentColor),
        attachmentAccentFillOpacity: 0.15,
        attachmentAccentBorderOpacity: 0.4,

        featureIconCapsule: Color(white: 0.15),

        tabIndicator: Color.white.opacity(0.6),

        tokenRingTrack: .gray.opacity(0.1),

        settingsCardFill: Color.white.opacity(0.03),
        settingsCardStroke: Color.white.opacity(0.1),

        splashBorder: Color(white: 0.3),

        typography: .default
    )
}

// MARK: - Default Light Theme

public extension Theme {
    /// A built-in light theme suitable for light-mode appearances.
    static let light = Theme(
        overlayBackdrop: Color.black.opacity(0.4),

        surfaceBackground: Color(nsColor: .controlBackgroundColor),
        surfaceSecondary: Color(nsColor: .textBackgroundColor).opacity(0.5),
        windowBackground: Color(nsColor: .windowBackgroundColor),

        selectedFill: Color.black.opacity(0.08),
        hoverFill: Color.black.opacity(0.04),
        highlightedFill: Color.black.opacity(0.1),

        border: Color.black.opacity(0.12),
        borderSubtle: Color.black.opacity(0.08),

        invertedContent: .white,

        destructive: Color.red,
        errorBackground: Color.red.opacity(0.08),
        errorBorder: Color.red.opacity(0.25),

        contextOverlayBackground: .white,
        contextOverlaySelection: Color.secondary.opacity(0.2),
        contextOverlayBorder: Color.black.opacity(0.15),

        attachmentAccent: Color(nsColor: .controlAccentColor),
        attachmentAccentFillOpacity: 0.1,
        attachmentAccentBorderOpacity: 0.3,

        featureIconCapsule: Color.black.opacity(0.06),

        tabIndicator: Color.black.opacity(0.5),

        tokenRingTrack: .gray.opacity(0.15),

        settingsCardFill: Color.black.opacity(0.02),
        settingsCardStroke: Color.black.opacity(0.08),

        splashBorder: Color.black.opacity(0.15),

        typography: .light
    )
}

// MARK: - Environment Key

private struct ThemeKey: EnvironmentKey {
    static let defaultValue: Theme = .dark
}

public extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

public extension View {
    func theme(_ theme: Theme) -> some View {
        environment(\.theme, theme)
    }
}
