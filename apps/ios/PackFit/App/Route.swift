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
    /// One photo of the pile; Claude names every object in it.
    case inventoryScan
    case suggestions
    case beforeYouGo
}

/// The three tabs from the Figma tab bar.
enum AppTab: Hashable {
    case home, results, plan
}

/// Lets any screen switch tabs, for example after packing to show the results.
@Observable
@MainActor
final class AppNavigator {
    var tab: AppTab = .home
}
