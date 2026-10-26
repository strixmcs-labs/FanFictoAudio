import AppKit
import SwiftUI

enum AppTheme {
    /// Oxblood in light mode; a lighter wine in dark mode that keeps text at 4.5:1 or better (brand guide, Labs applications).
    static let oxblood = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(red: 211 / 255.0, green: 113 / 255.0, blue: 129 / 255.0, alpha: 1) // #D37181: 4.5:1+ on dark backgrounds
            : NSColor(red: 101 / 255.0, green: 15 / 255.0, blue: 32 / 255.0, alpha: 1)
    })
    /// White in light mode, matching the original design; the system text background in dark mode.
    static let background = Color(nsColor: .textBackgroundColor)
    static let card = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .controlBackgroundColor : .white
    })
    static let wine = Color(red: 143 / 255.0, green: 48 / 255.0, blue: 64 / 255.0)
    static let bookGradient = LinearGradient(colors: [wine, oxblood], startPoint: .topLeading, endPoint: .bottomTrailing)
}
