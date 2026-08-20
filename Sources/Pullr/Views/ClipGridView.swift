import SwiftUI

struct ClipGridView: View {
    var items: [DownloadItem]

    private let columns = [
        GridItem(.adaptive(minimum: 276, maximum: 380), spacing: 14, alignment: .top)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(items) { item in
                    ClipCardView(item: item)
                }
            }
            .padding(2)
        }
        .scrollIndicators(.visible)
    }
}
