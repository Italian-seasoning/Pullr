import Foundation

enum MediaDeskLayout {
    static func inspectorWidth(availableWidth: Double, isVisible: Bool) -> Double {
        guard isVisible else { return 0 }
        return min(330, max(270, availableWidth * 0.30))
    }
}
