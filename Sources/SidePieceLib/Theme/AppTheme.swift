//
//  AppTheme.swift
//  SidePiece
//

import SwiftUI

public struct AppTheme: Sendable {
    let colors: ThemeColors
    let typography: ThemeTypography
    let spacing: ThemeSpacing
    let radius: ThemeRadius
    let borderWidth: ThemeBorderWidth
    
    public init(
        colors: ThemeColors,
        typography: ThemeTypography,
        spacing: ThemeSpacing,
        radius: ThemeRadius,
        borderWidth: ThemeBorderWidth
    ) {
        self.colors = colors
        self.typography = typography
        self.spacing = spacing
        self.radius = radius
        self.borderWidth = borderWidth
    }
}
