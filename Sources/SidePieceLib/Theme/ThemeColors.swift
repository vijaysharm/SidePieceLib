//
//  ThemeColors.swift
//  SidePiece
//

import SwiftUI

public struct ThemeColors: Sendable {

    // MARK: - Backgrounds

    let backgroundPrimary: Color
    let backgroundSecondary: Color
    let backgroundInput: Color
    let backgroundOverlay: Color
    let scrim: Color

    // MARK: - Surfaces

    let surfaceHover: Color
    let surfaceSelected: Color
    let surfaceSubtle: Color

    // MARK: - Text

    let textPrimary: Color
    let textSecondary: Color
    let textTertiary: Color
    let textOnSelected: Color
    let textOnSelectedSecondary: Color

    // MARK: - Borders

    let border: Color
    let borderSubtle: Color
    let borderActive: Color
    let separator: Color

    // MARK: - Accent

    let accent: Color
    let accentSubtle: Color

    // MARK: - Status

    let statusError: Color
    let statusErrorBackground: Color
    let statusErrorBorder: Color
    let statusSuccess: Color
    let statusWarning: Color
    let statusWarningIntense: Color
    let statusInfo: Color

    // MARK: - Feature badges

    let featureFast: Color
    let featureVision: Color
    let featureReasoning: Color
    let featureToolCalling: Color
    let featureImageGen: Color
    let featurePDF: Color
    let featureBadgeBackground: Color
}
