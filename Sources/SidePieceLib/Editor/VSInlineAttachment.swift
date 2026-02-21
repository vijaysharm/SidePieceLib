//
//  VSInlineAttachment.swift
//  SidePiece
//

#if os(macOS)
@preconcurrency import AppKit
import ComposableArchitecture
import SwiftUI
import UniformTypeIdentifiers

final class VSInlineAttachment: NSTextAttachment {
    public struct VSAttachmentModel: Sendable, Equatable, Identifiable {
        public enum ModelType: Sendable, Equatable {
            case file(URL, UTType)
            case tool(String, Image)
            
            var title: String {
                switch self {
                case let .file(url, _):
                    url.lastPathComponent
                case let .tool(name, _):
                    name
                }
            }
            
            var image: Image {
                switch self {
                case let .file(_, type):
                    type.icon
                case let .tool(_, image):
                    image
                }
            }
        }
        
        let id: UUID
        let type: ModelType
    }
    
    public let data: VSAttachmentModel
    private let font: NSFont
    private let padding: CGFloat = 6
    private let cornerRadius: CGFloat = 4
    private let closeButtonSize: CGFloat = 14
    
    // Expose the close button hit area (relative to attachment bounds)
    private(set) var closeButtonRect: CGRect = .zero
    
    init(
        data: VSAttachmentModel,
        font: NSFont
    ) {
        self.data = data
        self.font = font
        
        super.init(data: nil, ofType: nil)
        
        // Generate and set the image immediately - no viewProvider, no timing issues
        let image = attachmentImage()
        self.image = image
        self.bounds = CGRect(
            origin: .zero,
            size: image.size
        )
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    /// Check if a point (relative to attachment bounds) hits the close button
    func didTapCloseButton(at point: CGPoint) -> Bool {
        // Expand hit area slightly for easier clicking
        let expandedRect = closeButtonRect.insetBy(dx: -4, dy: -4)
        return expandedRect.contains(point)
    }
    
    // Override to provide proper baseline offset
    override func attachmentBounds(
        for textContainer: NSTextContainer?,
        proposedLineFragment lineFrag: CGRect,
        glyphPosition position: CGPoint,
        characterIndex charIndex: Int
    ) -> CGRect {
        let imageSize = image?.size ?? .zero
        
        // We want the text inside the chip to align with the text outside.
        // The chip is taller than the text, so we need to push it down.
        // The `y` origin of attachmentBounds is relative to the baseline.
        // A negative `y` moves the image down.
        
        // Center the text vertically within the chip
        // Chip Height = imageSize.height
        // Text Height (approx) = font.ascender - font.descender
        
        // Align baselines:
        // The text baseline inside the image is at `padding + (height - textSize.height)/2 + textAscender` from bottom?
        // Simpler: The image should be shifted down by `descender + (chipHeight - lineHeight)/2`
        
        // Let's try to center the chip on the cap height of the surrounding text
        // Or better: Align the baseline of the text inside the chip with the baseline of the line.
        
        // The text is drawn centered vertically in the image.
        // Top of text in image is at `(imageHeight - textHeight) / 2`
        // Baseline of text in image is at `Top + Ascender`
        
        // We want that internal baseline to align with the line's baseline (y=0).
        // So we need to shift the image so that point is at y=0.
        
        let textHeight = font.ascender - font.descender
        let verticalPadding = (imageSize.height - textHeight) / 2
        
        // Distance from top of image to baseline of text inside image
        let internalBaselineFromTop = verticalPadding + font.ascender
        
        // We want to shift the image down so that internalBaselineFromTop is at y=0
        // Since y increases upwards in some contexts but downwards in drawing...
        // For attachmentBounds, y is offset from baseline. Positive is up.
        
        // If we draw the image at (0, yOffset), the top of the image is at yOffset + imageHeight (or just yOffset if flipped).
        // Standard attachments sit on the baseline.
        
        // We need to move the image down by the distance from the bottom of the image to the text baseline.
        // Bottom to Baseline = TotalHeight - TopToBaseline
        let baselineFromBottom = imageSize.height - internalBaselineFromTop
        
        // We want to shift down by this amount + font descender?
        // Let's just shift it down so the visual center aligns with text visual center
        // Or strictly align baselines.
        
        // Shift down by the distance from the bottom of the image to the baseline
        // y = -baselineFromBottom
        
        return CGRect(
            x: 0,
            y: -baselineFromBottom,
            width: imageSize.width,
            height: imageSize.height
        )
    }
    
    private func attachmentImage() -> NSImage {
        let displayText = data.type.title
        let displayIcon = data.type.image
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white
        ]
        
        // Calculate text size
        let textSize = (displayText as NSString).size(withAttributes: textAttributes)
        
        // Layout: [padding] [icon] [gap] [text] [gap] [closeButton] [padding]
        let iconSize: CGFloat = font.pointSize
        let gap: CGFloat = 4
        
        let contentWidth = iconSize + gap + textSize.width + gap + closeButtonSize
        let imageSize = NSSize(
            width: ceil(contentWidth + padding * 2),
            height: ceil(max(textSize.height, closeButtonSize) + padding)
        )
        
        // Calculate close button rect (will be used for hit testing)
        let closeButtonX = imageSize.width - padding - closeButtonSize
        let closeButtonY = (imageSize.height - closeButtonSize) / 2
        self.closeButtonRect = CGRect(
            x: closeButtonX,
            y: closeButtonY,
            width: closeButtonSize,
            height: closeButtonSize
        )
        
        // Use flipped coordinates (standard for macOS text drawing)
        let image = NSImage(
            size: imageSize,
            flipped: false
        ) { [padding, cornerRadius, closeButtonSize, closeButtonRect, iconSize, gap] rect in
            // Draw rounded background
            let bgPath = NSBezierPath(
                roundedRect: rect.insetBy(dx: 1, dy: 1),
                xRadius: cornerRadius,
                yRadius: cornerRadius
            )
            NSColor.controlAccentColor
                .withAlphaComponent(0.15)
                .setFill()
            bgPath.fill()
            
            // Draw border
            NSColor.controlAccentColor
                .withAlphaComponent(0.4)
                .setStroke()
            bgPath.lineWidth = 1
            bgPath.stroke()
            
            // Draw file icon on the left
            let iconRect = NSRect(
                x: padding,
                y: (rect.height - iconSize) / 2,
                width: iconSize,
                height: iconSize
            )
            
            if let fileIcon = NSImage.nsImage(
                from: displayIcon,
                size: NSRect(origin: .zero, size: CGSize(width: iconSize, height: iconSize)),
                tint: .white
            ) {
                fileIcon.draw(
                    in: iconRect,
                    from: .zero,
                    operation: .sourceOver,
                    fraction: 1.0
                )
            }
            
            // Draw text
            let textX = padding + iconSize + gap
            let textRect = NSRect(
                x: textX,
                y: (rect.height - textSize.height) / 2,
                width: textSize.width,
                height: textSize.height
            )
            (displayText as NSString).draw(in: textRect, withAttributes: textAttributes)
            
            // Draw close button (X icon)
            if let closeIcon = NSImage(
                systemSymbolName: "xmark.circle.fill",
                accessibilityDescription: "Remove"
            ) {
                let config = NSImage.SymbolConfiguration(
                    pointSize: closeButtonSize - 2,
                    weight: .medium
                )
                
                // Apply white color directly to the symbol configuration
                let whiteConfig = config.applying(.init(hierarchicalColor: .white))
                let whiteIcon = closeIcon.withSymbolConfiguration(whiteConfig)
                
                whiteIcon?.draw(
                    in: closeButtonRect,
                    from: .zero,
                    operation: .sourceOver,
                    fraction: 0.7
                )
            }
            
            return true
        }
        
        image.isTemplate = false
        return image
    }
}

private extension NSImage {
    static func nsImage(from image: Image, size: NSRect, tint: Color? = nil) -> NSImage? {
        MainActor.assumeIsolated {
            // Apply tint color in SwiftUI before rendering - this works for SF Symbols
            let styledImage = if let tint {
                AnyView(image.foregroundStyle(tint).frame(width: size.width, height: size.height))
            } else {
                AnyView(image.frame(width: size.width, height: size.height))
            }
            let renderer = ImageRenderer(content: styledImage)
            renderer.scale = NSScreen.main?.backingScaleFactor ?? 2.0
            return renderer.nsImage
        }
    }
}
#endif
