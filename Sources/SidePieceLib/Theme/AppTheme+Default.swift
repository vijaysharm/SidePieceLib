//
//  AppTheme+Default.swift
//  SidePiece
//

import SwiftUI

extension AppTheme {
    public static let `default` = AppTheme(
        colors: .default,
        typography: .default,
        spacing: .default,
        radius: .default,
        borderWidth: .default
    )
}

// MARK: - Colors

extension ThemeColors {
    public static let `default` = ThemeColors(
        // Backgrounds
        backgroundPrimary: Color(light: Color(white: 0.98), dark: Color(white: 0.1)),
        backgroundSecondary: Color(light: Color(white: 0.94), dark: Color(white: 0.15)),
        backgroundInput: Color(light: .white, dark: Color(white: 0.1)),
        backgroundOverlay: Color(light: Color(white: 0.96), dark: Color(white: 0.15)),
        scrim: Color(light: Color.black.opacity(0.4), dark: Color.black.opacity(0.85)),

        // Surfaces
        surfaceHover: Color(light: Color.black.opacity(0.04), dark: Color.white.opacity(0.05)),
        surfaceSelected: Color(light: Color.black.opacity(0.06), dark: Color.white.opacity(0.1)),
        surfaceSubtle: Color(light: Color.black.opacity(0.02), dark: Color.white.opacity(0.03)),

        // Text
        textPrimary: .primary,
        textSecondary: .secondary,
        textTertiary: Color(light: Color.black.opacity(0.4), dark: Color.white.opacity(0.5)),
        textOnSelected: Color(light: .black, dark: .white),
        textOnSelectedSecondary: Color(light: Color.black.opacity(0.6), dark: Color.white.opacity(0.6)),

        // Borders
        border: Color(light: Color.black.opacity(0.12), dark: Color.white.opacity(0.15)),
        borderSubtle: Color(light: Color.black.opacity(0.08), dark: Color.white.opacity(0.1)),
        borderActive: Color.accentColor,
        separator: Color(light: Color.black.opacity(0.1), dark: Color(white: 0.3)),

        // Accent
        accent: Color.accentColor,
        accentSubtle: Color(light: Color.accentColor.opacity(0.1), dark: Color.accentColor.opacity(0.1)),

        // Status
        statusError: Color.red,
        statusErrorBackground: Color(light: Color.red.opacity(0.08), dark: Color.red.opacity(0.1)),
        statusErrorBorder: Color(light: Color.red.opacity(0.2), dark: Color.red.opacity(0.3)),
        statusSuccess: Color.green,
        statusWarning: Color.orange,
        statusWarningIntense: Color.yellow,
        statusInfo: Color.blue,

        // Feature badges
        featureFast: .yellow,
        featureVision: .green,
        featureReasoning: .purple,
        featureToolCalling: .blue,
        featureImageGen: Color.purple.opacity(0.8),
        featurePDF: .cyan,
        featureBadgeBackground: Color(light: Color.black.opacity(0.05), dark: Color.white.opacity(0.1))
    )
}

// MARK: - Typography

extension ThemeTypography {
    public static let `default` = ThemeTypography(
        displayIcon: .system(size: 36),
        featureIcon: .system(size: 24),
        alertIcon: .system(size: 20),

        body: .system(size: 15),
        bodySmall: .system(size: 13),
        label: .system(size: 14),

        caption: .system(size: 11),
        captionSmall: .system(size: 10),
        micro: .system(size: 9),
        legal: .system(size: 8),

        monoSmall: .system(size: 12, design: .monospaced),
        monoBody: .system(size: 15, design: .monospaced),
        monoCaption: .system(size: 11, design: .monospaced),

        bodySizePt: 15,
        bodySmallSizePt: 13,
        monoSmallSizePt: 12,
        monoBodySizePt: 15
    )
}

// MARK: - Spacing

extension ThemeSpacing {
    public static let `default` = ThemeSpacing(
        xxs: 2,
        xs: 4,
        sm: 6,
        md: 8,
        lg: 12,
        xl: 16,
        xxl: 24,
        xxxl: 40
    )
}

// MARK: - Radius

extension ThemeRadius {
    public static let `default` = ThemeRadius(
        xs: 4,
        sm: 6,
        md: 8,
        lg: 12,
        xl: 14,
        pill: 16
    )
}

// MARK: - Border Width

extension ThemeBorderWidth {
    public static let `default` = ThemeBorderWidth(
        hairline: 0.5,
        thin: 1,
        medium: 2,
        thick: 2.5,
        indicator: 3
    )
}
