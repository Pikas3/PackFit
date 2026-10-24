import Foundation

enum Route: Hashable {
    case tripPicker
    case bagSetup
    case itemList
    case scan
    case planViewer
    case rules
    case arOverlay
    /// LiDAR flow: scan the open bag, sweep the items, plan inside the real bag.
    case guidedScan
    case suggestions
    case beforeYouGo
    /// One photo of the pile; Claude names every object in it.
    case inventoryScan
}
