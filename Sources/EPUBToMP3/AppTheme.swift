import SwiftUI

enum AppTheme {
    static let oxblood = Color(red: 101 / 255.0, green: 15 / 255.0, blue: 32 / 255.0)
    static let wine = Color(red: 143 / 255.0, green: 48 / 255.0, blue: 64 / 255.0)
    static let bookGradient = LinearGradient(colors: [wine, oxblood], startPoint: .topLeading, endPoint: .bottomTrailing)
}
