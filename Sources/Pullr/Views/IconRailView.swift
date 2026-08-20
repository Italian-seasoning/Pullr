import SwiftUI

struct IconRailView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(spacing: 11) {
            PullrLogoMark()

            Divider()
                .overlay(.white.opacity(0.10))
                .frame(width: 28)
                .padding(.vertical, 2)

            ForEach(AppSection.allCases) { section in
                IconRailButton(
                    title: section.title,
                    systemImage: section.systemImage,
                    isSelected: store.selectedSection == section
                ) {
                    store.selectedSection = section
                }
            }

            Spacer(minLength: 0)
        }
        .padding(9)
        .frame(width: 64)
        .glassPanel(cornerRadius: 22)
    }
}

private struct PullrLogoMark: View {
    var body: some View {
        Image(systemName: "play.rectangle.fill")
            .font(.system(size: 21, weight: .semibold))
            .foregroundStyle(AppTheme.primaryText)
            .frame(width: 36, height: 36)
            .background(AppTheme.panelFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(AppTheme.panelStroke, lineWidth: 0.5)
            }
        .accessibilityHidden(true)
        .padding(.vertical, 4)
    }
}
