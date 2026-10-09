import SwiftUI

enum AppTheme {
    static let baseBackground = Color(red: 0.055, green: 0.065, blue: 0.065)
    static let glassTint = Color(red: 0.085, green: 0.100, blue: 0.098)
    static let panelFill = Color(red: 0.043, green: 0.046, blue: 0.052).opacity(0.96)
    static let panelStroke = Color.white.opacity(0.14)
    static let selectedStroke = accent.opacity(0.50)
    static let selectedFill = Color(red: 0.052, green: 0.070, blue: 0.105).opacity(0.97)
    static let primaryText = Color.white.opacity(0.92)
    static let secondaryText = Color.white.opacity(0.68)
    static let tertiaryText = Color.white.opacity(0.56)
    static let accent = Color(red: 0.65, green: 0.82, blue: 0.70)
    static let subtleAccent = Color(red: 0.62, green: 0.76, blue: 0.96)
    static let warning = Color(red: 0.92, green: 0.72, blue: 0.38)
    static let danger = Color(red: 0.94, green: 0.40, blue: 0.36)
    static let success = Color(red: 0.57, green: 0.80, blue: 0.64)
    static let panelShadow = Color.black.opacity(0.40)
    static let thumbnailFill = Color(red: 0.026, green: 0.028, blue: 0.034).opacity(0.88)
}

extension Animation {
    static var pullrMicro: Animation {
        .easeOut(duration: 0.16)
    }

    static var pullrPanel: Animation {
        .easeInOut(duration: 0.24)
    }
}
