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
    
    public init(
        backgroundPrimary: Color,
        backgroundSecondary: Color,
        backgroundInput: Color,
        backgroundOverlay: Color,
        scrim: Color,
        surfaceHover: Color,
        surfaceSelected: Color,
        surfaceSubtle: Color,
        textPrimary: Color,
        textSecondary: Color,
        textTertiary: Color,
        textOnSelected: Color,
        textOnSelectedSecondary: Color,
        border: Color,
        borderSubtle: Color,
        borderActive: Color,
        separator: Color,
        accent: Color,
        accentSubtle: Color,
        statusError: Color,
        statusErrorBackground: Color,
        statusErrorBorder: Color,
        statusSuccess: Color,
        statusWarning: Color,
        statusWarningIntense: Color,
        statusInfo: Color,
        featureFast: Color,
        featureVision: Color,
        featureReasoning: Color,
        featureToolCalling: Color,
        featureImageGen: Color,
        featurePDF: Color,
        featureBadgeBackground: Color
    ) {
        self.backgroundPrimary = backgroundPrimary
        self.backgroundSecondary = backgroundSecondary
        self.backgroundInput = backgroundInput
        self.backgroundOverlay = backgroundOverlay
        self.scrim = scrim
        self.surfaceHover = surfaceHover
        self.surfaceSelected = surfaceSelected
        self.surfaceSubtle = surfaceSubtle
        self.textPrimary = textPrimary
        self.textSecondary = textSecondary
        self.textTertiary = textTertiary
        self.textOnSelected = textOnSelected
        self.textOnSelectedSecondary = textOnSelectedSecondary
        self.border = border
        self.borderSubtle = borderSubtle
        self.borderActive = borderActive
        self.separator = separator
        self.accent = accent
        self.accentSubtle = accentSubtle
        self.statusError = statusError
        self.statusErrorBackground = statusErrorBackground
        self.statusErrorBorder = statusErrorBorder
        self.statusSuccess = statusSuccess
        self.statusWarning = statusWarning
        self.statusWarningIntense = statusWarningIntense
        self.statusInfo = statusInfo
        self.featureFast = featureFast
        self.featureVision = featureVision
        self.featureReasoning = featureReasoning
        self.featureToolCalling = featureToolCalling
        self.featureImageGen = featureImageGen
        self.featurePDF = featurePDF
        self.featureBadgeBackground = featureBadgeBackground
    }
}
