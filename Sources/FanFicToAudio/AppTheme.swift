import AppKit
import SwiftUI

enum AppTheme {
    /// Oxblood in light mode; a lighter wine in dark mode so text and controls keep their contrast.
    static let oxblood = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(red: 0.80, green: 0.36, blue: 0.43, alpha: 1)
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
