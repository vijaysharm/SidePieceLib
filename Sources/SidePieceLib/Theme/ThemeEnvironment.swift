//
//  ThemeEnvironment.swift
//  SidePiece
//

import SwiftUI

// MARK: - Environment Key

private struct ThemeKey: EnvironmentKey {
    static let defaultValue: AppTheme = .default
}

extension EnvironmentValues {
    var theme: AppTheme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

// MARK: - View Modifier

extension View {
    /// Injects the app theme into the environment for all descendant views.
    public func appTheme(_ theme: AppTheme = .default) -> some View {
        environment(\.theme, theme)
    }
}
