import Foundation

struct PlaylistOptions: Codable, Hashable {
    var createPlaylistFolder: Bool
    var rangeStart: Int?
    var rangeEnd: Int?
    var reverseOrder: Bool

    init(
        createPlaylistFolder: Bool = true,
        rangeStart: Int? = nil,
        rangeEnd: Int? = nil,
        reverseOrder: Bool = false
    ) {
        self.createPlaylistFolder = createPlaylistFolder
        self.rangeStart = rangeStart
        self.rangeEnd = rangeEnd
        self.reverseOrder = reverseOrder
    }

    var playlistItemsArgument: String? {
        switch (rangeStart, rangeEnd) {
        case (.some(let start), .some(let end)):
            "\(max(1, start)):\(max(start, end))"
        case (.some(let start), .none):
            "\(max(1, start)):"
        case (.none, .some(let end)):
            "1:\(max(1, end))"
        case (.none, .none):
            nil
        }
    }
}
