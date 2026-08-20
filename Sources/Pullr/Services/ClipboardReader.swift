import AppKit

struct ClipboardReader {
    var changeCount: Int {
        NSPasteboard.general.changeCount
    }

    func readString() -> String? {
        NSPasteboard.general.string(forType: .string)
    }
}
