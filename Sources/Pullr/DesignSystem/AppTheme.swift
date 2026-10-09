import SwiftUI

enum AppTheme {
    static let baseBackground = Color(white: 0.06)
    static let glassTint = Color(white: 0.10)
    static let panelFill = Color(red: 0.043, green: 0.046, blue: 0.052).opacity(0.96)
    static let panelStroke = Color.white.opacity(0.14)
    static let selectedStroke = accent.opacity(0.50)
    static let selectedFill = Color(white: 0.16)
    static let primaryText = Color.white.opacity(0.92)
    static let secondaryText = Color.white.opacity(0.68)
    static let tertiaryText = Color.white.opacity(0.56)
    static let accent = Color(white: 0.83)
    static let subtleAccent = Color(white: 0.67)
    static let warning = Color(red: 0.92, green: 0.72, blue: 0.38)
    static let danger = Color(red: 0.94, green: 0.40, blue: 0.36)
    static let success = Color(white: 0.75)
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
