import SwiftUI

struct GlassPanel<Content: View>: View {
    var cornerRadius: CGFloat = 18
    var material: Material = .ultraThinMaterial
    var selected = false
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content
            .background(material, in: shape)
            .background(
                shape.fill(selected ? AppTheme.selectedFill.opacity(0.72) : AppTheme.glassTint)
            )
            .overlay(alignment: .top) {
                LinearGradient(
                    colors: [
                        .clear,
                        .white.opacity(selected ? 0.16 : 0.09),
                        .white.opacity(selected ? 0.10 : 0.055),
                        .clear
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(height: 1)
                .padding(.horizontal, max(12, cornerRadius * 0.72))
                .padding(.top, 0.5)
                .allowsHitTesting(false)
            }
            .overlay {
                shape
                    .stroke(
                        LinearGradient(
                            colors: [
                                .white.opacity(selected ? 0.42 : 0.30),
                                selected ? AppTheme.selectedStroke : .white.opacity(0.07),
                                .white.opacity(selected ? 0.22 : 0.14)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: selected ? 1.2 : 0.85
                    )
            }
            .overlay {
                shape
                    .inset(by: 1.5)
                    .stroke(.white.opacity(0.045), lineWidth: 1)
            }
            .contentShape(shape)
            .shadow(color: AppTheme.panelShadow, radius: 8, y: 4)
            .shadow(color: selected ? AppTheme.accent.opacity(0.14) : .clear, radius: 8, y: 3)
            .compositingGroup()
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
