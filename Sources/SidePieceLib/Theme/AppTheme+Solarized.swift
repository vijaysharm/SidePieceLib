//
//  AppTheme+Solarized.swift
//  SidePiece
//

import SwiftUI

// MARK: - Solarized Palette

private enum Sol {
    // Base tones
    static let base03  = Color(hex: 0x002b36)
    static let base02  = Color(hex: 0x073642)
    static let base01  = Color(hex: 0x586e75)
    static let base00  = Color(hex: 0x657b83)
    static let base0   = Color(hex: 0x839496)
    static let base1   = Color(hex: 0x93a1a1)
    static let base2   = Color(hex: 0xeee8d5)
    static let base3   = Color(hex: 0xfdf6e3)

    // Accents
    static let yellow  = Color(hex: 0xb58900)
    static let orange  = Color(hex: 0xcb4b16)
    static let red     = Color(hex: 0xdc322f)
    static let magenta = Color(hex: 0xd33682)
    static let violet  = Color(hex: 0x6c71c4)
    static let blue    = Color(hex: 0x268bd2)
    static let cyan    = Color(hex: 0x2aa198)
    static let green   = Color(hex: 0x859900)
}

// MARK: - Theme

extension AppTheme {
    public static let solarized = AppTheme(
        colors: .solarized,
        typography: .solarized,
        spacing: .default,
        radius: .solarized,
        borderWidth: .solarized
    )
}

// MARK: - Colors

extension ThemeColors {
    static let solarized = ThemeColors(
        // Backgrounds
        backgroundPrimary: Color(light: Sol.base3, dark: Sol.base03),
        backgroundSecondary: Color(light: Sol.base2, dark: Sol.base02),
        backgroundInput: Color(light: .white, dark: Sol.base03),
        backgroundOverlay: Color(light: Sol.base2, dark: Sol.base02),
        scrim: Color(light: Sol.base03.opacity(0.4), dark: Sol.base03.opacity(0.85)),

        // Surfaces
        surfaceHover: Color(light: Sol.base2.opacity(0.6), dark: Sol.base02.opacity(0.6)),
        surfaceSelected: Color(light: Sol.base2, dark: Sol.base02),
        surfaceSubtle: Color(light: Sol.base2.opacity(0.3), dark: Sol.base02.opacity(0.3)),

        // Text
        textPrimary: Color(light: Sol.base00, dark: Sol.base0),
        textSecondary: Color(light: Sol.base1, dark: Sol.base01),
        textTertiary: Color(light: Sol.base1.opacity(0.6), dark: Sol.base01.opacity(0.6)),
        textOnSelected: Color(light: Sol.base03, dark: Sol.base3),
        textOnSelectedSecondary: Color(light: Sol.base03.opacity(0.6), dark: Sol.base3.opacity(0.6)),

        // Borders
        border: Color(light: Sol.base1.opacity(0.3), dark: Sol.base01.opacity(0.3)),
        borderSubtle: Color(light: Sol.base1.opacity(0.15), dark: Sol.base01.opacity(0.15)),
        borderActive: Sol.cyan,
        separator: Color(light: Sol.base1.opacity(0.2), dark: Sol.base01.opacity(0.2)),

        // Accent
        accent: Sol.cyan,
        accentSubtle: Color(light: Sol.cyan.opacity(0.1), dark: Sol.cyan.opacity(0.15)),

        // Status
        statusError: Sol.red,
        statusErrorBackground: Color(light: Sol.red.opacity(0.08), dark: Sol.red.opacity(0.12)),
        statusErrorBorder: Color(light: Sol.red.opacity(0.2), dark: Sol.red.opacity(0.3)),
        statusSuccess: Sol.green,
        statusWarning: Sol.orange,
        statusWarningIntense: Sol.yellow,
        statusInfo: Sol.blue,

        // Feature badges
        featureFast: Sol.yellow,
        featureVision: Sol.green,
        featureReasoning: Sol.violet,
        featureToolCalling: Sol.blue,
        featureImageGen: Sol.magenta,
        featurePDF: Sol.cyan,
        featureBadgeBackground: Color(light: Sol.base2, dark: Sol.base02)
    )
}

// MARK: - Typography

extension ThemeTypography {
    public static let solarized = ThemeTypography(
        displayIcon: .system(size: 36, design: .monospaced),
        featureIcon: .system(size: 24, design: .monospaced),
        alertIcon: .system(size: 20, design: .monospaced),

        title: .system(size: 28, design: .monospaced),
        titleSmall: .system(size: 22, design: .monospaced),
        heading: .system(size: 17, design: .monospaced),

        body: .system(size: 15, design: .monospaced),
        bodySmall: .system(size: 13, design: .monospaced),
        label: .system(size: 14, design: .monospaced),

        caption: .system(size: 11, design: .monospaced),
        captionSmall: .system(size: 10, design: .monospaced),
        micro: .system(size: 9, design: .monospaced),
        legal: .system(size: 8, design: .monospaced),

        monoSmall: .system(size: 12, design: .monospaced),
        monoBody: .system(size: 15, design: .monospaced),
        monoCaption: .system(size: 11, design: .monospaced),

        bodySizePt: 15,
        bodySmallSizePt: 13,
        monoSmallSizePt: 12,
        monoBodySizePt: 15
    )
}

// MARK: - Radius

extension ThemeRadius {
    public static let solarized = ThemeRadius(
        xs: 2,
        sm: 3,
        md: 4,
        lg: 6,
        xl: 8,
        pill: 10
    )
}

// MARK: - Border Width

extension ThemeBorderWidth {
    public static let solarized = ThemeBorderWidth(
        hairline: 1,
        thin: 1.5,
        medium: 2,
        thick: 3,
        indicator: 3.5
    )
}
