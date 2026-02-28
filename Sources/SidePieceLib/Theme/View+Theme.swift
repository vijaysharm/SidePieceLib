//
//  View+Theme.swift
//  SidePiece
//

import SwiftUI

extension View {
    /// Applies a standard card background: subtle fill + border + corner radius.
    func themedCard(theme: AppTheme) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: theme.radius.md)
                    .fill(theme.colors.surfaceSubtle)
            )
            .overlay(
                RoundedRectangle(cornerRadius: theme.radius.md)
                    .stroke(theme.colors.borderSubtle, lineWidth: theme.borderWidth.thin)
            )
    }

    /// Applies a row background that responds to hover and selection state.
    func themedRowBackground(
        isSelected: Bool,
        isHovered: Bool,
        theme: AppTheme,
        radius: CGFloat? = nil
    ) -> some View {
        let r = radius ?? theme.radius.sm
        return self.background(
            RoundedRectangle(cornerRadius: r)
                .fill(
                    isSelected
                        ? theme.colors.surfaceSelected
                        : isHovered
                            ? theme.colors.surfaceHover
                            : Color.clear
                )
        )
    }

    /// Applies a scrim overlay (dimmed background behind modals/overlays).
    func themedScrim(theme: AppTheme) -> some View {
        self.background(theme.colors.scrim.ignoresSafeArea())
    }
}
