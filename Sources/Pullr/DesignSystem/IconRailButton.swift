import SwiftUI

struct IconRailButton: View {
    var title: String
    var systemImage: String
    var isSelected: Bool
    var action: () -> Void

    @State private var isHovered = false
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? AppTheme.primaryText : AppTheme.secondaryText)
                .frame(width: 42, height: 42)
                .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
        .focusable()
        .focused($isFocused)
        .help(title)
        .accessibilityLabel(title)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(isSelected ? AppTheme.accent.opacity(0.18) : .white.opacity(isHovered ? 0.075 : 0.025))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(isFocused ? AppTheme.subtleAccent.opacity(0.9) : (isSelected ? AppTheme.accent.opacity(0.28) : .white.opacity(0.06)), lineWidth: isFocused ? 1.4 : 0.6)
        }
        .scaleEffect(isHovered ? 1.035 : 1)
        .animation(.pullrMicro, value: isHovered)
        .animation(.pullrMicro, value: isSelected)
        .onHover { isHovered = $0 }
    }
}
