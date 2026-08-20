import SwiftUI

struct ClipListView: View {
    var items: [DownloadItem]

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(items) { item in
                    ClipRowView(item: item)
                }
            }
            .padding(2)
        }
        .scrollIndicators(.visible)
    }
}
