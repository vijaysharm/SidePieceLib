//
//  ThemeTypography.swift
//  SidePiece
//

import SwiftUI

public struct ThemeTypography: Sendable {

    // MARK: - Display / Icon sizes

    let displayIcon: Font   // 36
    let featureIcon: Font   // 24
    let alertIcon: Font     // 20

    // MARK: - Titles

    let title: Font         // 28
    let titleSmall: Font    // 22
    let heading: Font       // 17

    // MARK: - Body

    let body: Font          // 15
    let bodySmall: Font     // 13
    let label: Font         // 14

    // MARK: - Caption

    let caption: Font       // 11
    let captionSmall: Font  // 10
    let micro: Font         // 9
    let legal: Font         // 8

    // MARK: - Monospaced

    let monoSmall: Font     // 12 mono
    let monoBody: Font      // 15 mono
    let monoCaption: Font   // 11 mono

    // MARK: - Raw sizes (for layout calculations that need CGFloat)

    let bodySizePt: CGFloat       // 15
    let bodySmallSizePt: CGFloat  // 13
    let monoSmallSizePt: CGFloat  // 12
    let monoBodySizePt: CGFloat   // 15
}
