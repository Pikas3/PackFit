import Foundation

enum Route: Hashable {
    case tripPicker
    case bagSetup
    case itemList
    case planViewer
    case rules
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
