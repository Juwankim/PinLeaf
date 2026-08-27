//
//  NoteColor+UI.swift
//  PinLeaf
//

import AppKit
import SwiftUI

extension NoteColor {
    var backgroundColor: Color {
        switch self {
        case .yellow:
            Color(red: 1.00, green: 0.95, blue: 0.64)
        case .pink:
            Color(red: 1.00, green: 0.82, blue: 0.88)
        case .blue:
            Color(red: 0.80, green: 0.91, blue: 1.00)
        case .green:
            Color(red: 0.84, green: 0.94, blue: 0.78)
        case .purple:
            Color(red: 0.90, green: 0.84, blue: 0.98)
        }
    }

    var appKitBackgroundColor: NSColor {
        switch self {
        case .yellow:
            NSColor(calibratedRed: 1.00, green: 0.95, blue: 0.64, alpha: 1)
        case .pink:
            NSColor(calibratedRed: 1.00, green: 0.82, blue: 0.88, alpha: 1)
        case .blue:
            NSColor(calibratedRed: 0.80, green: 0.91, blue: 1.00, alpha: 1)
        case .green:
            NSColor(calibratedRed: 0.84, green: 0.94, blue: 0.78, alpha: 1)
        case .purple:
            NSColor(calibratedRed: 0.90, green: 0.84, blue: 0.98, alpha: 1)
        }
    }

    var mutedListBackgroundColor: Color {
        let mutedColor = appKitBackgroundColor.blended(
            withFraction: 0.72,
            of: .white
        ) ?? appKitBackgroundColor
        return Color(nsColor: mutedColor)
    }

    /// A non-template image keeps its real color when AppKit renders it in an NSMenu.
    var menuSwatchImage: NSImage {
        let size = NSSize(width: 16, height: 16)
        let image = NSImage(size: size, flipped: false) { rect in
            let swatchRect = rect.insetBy(dx: 1, dy: 1)
            let swatch = NSBezierPath(
                roundedRect: swatchRect,
                xRadius: 4,
                yRadius: 4
            )
            self.appKitBackgroundColor.setFill()
            swatch.fill()

            NSColor.black.withAlphaComponent(0.18).setStroke()
            swatch.lineWidth = 1
            swatch.stroke()
            return true
        }
        image.isTemplate = false
        return image
    }
}
