import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case presets
    case downloads
    case dependencies
    case playlists
    case advanced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .presets: "Presets"
        case .downloads: "Downloads"
        case .dependencies: "Dependencies"
        case .playlists: "Playlists"
        case .advanced: "Advanced"
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    var isStandalone = false
    @State private var selectedTab: SettingsTab = .presets

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Settings Section", selection: $selectedTab) {
                ForEach(SettingsTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 1040)

            Group {
                switch selectedTab {
                case .presets:
                    PresetManagerView()
                case .downloads:
                    DownloadsSettingsView()
                case .dependencies:
                    DependencySettingsView()
                case .playlists:
                    PlaylistSettingsView()
                case .advanced:
                    AdvancedSettingsView()
                }
            }
            .frame(maxWidth: 1040, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(isStandalone ? 18 : 0)
        .frame(
            minWidth: isStandalone ? 760 : nil,
            idealWidth: isStandalone ? 860 : nil,
            minHeight: isStandalone ? 540 : nil,
            idealHeight: isStandalone ? 640 : nil
        )
        .background(isStandalone ? AppTheme.baseBackground : .clear)
        .onChange(of: store.settings) { _, _ in
            store.saveSettings()
        }
    }
}
