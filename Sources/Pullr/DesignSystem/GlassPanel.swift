import SwiftUI

struct GlassPanel<Content: View>: View {
    var cornerRadius: CGFloat = 18
    var material: Material = .ultraThinMaterial
    var selected = false
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content
            .background(
                shape.fill(selected ? AppTheme.selectedFill : AppTheme.glassTint)
            )
            .overlay {
                shape
                    .stroke(selected ? AppTheme.selectedStroke : AppTheme.panelStroke, lineWidth: 1)
            }
            .contentShape(shape)
    }
}

private struct GlassPanelModifier: ViewModifier {
    var cornerRadius: CGFloat
    var material: Material
    var selected: Bool

    func body(content: Content) -> some View {
        GlassPanel(cornerRadius: cornerRadius, material: material, selected: selected) {
            content
        }
    }
}

extension View {
    func glassPanel(cornerRadius: CGFloat = 18, material: Material = .ultraThinMaterial, selected: Bool = false) -> some View {
        modifier(GlassPanelModifier(cornerRadius: cornerRadius, material: material, selected: selected))
    }
}
