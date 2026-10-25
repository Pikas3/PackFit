import SwiftUI
import UIKit

@main
struct PackFitApp: App {
    @State private var tripStore = TripStore()
    @State private var itemsStore = ItemsStore()
    @State private var planStore = PlanStore()
    @State private var rulesStore = RulesStore()

    init() {
        Self.applyBarFonts()
    }

    /// Navigation and tab bar titles are UIKit, so they take the bundled fonts here.
    private static func applyBarFonts() {
        let ink = UIColor(Tokens.Palette.textPrimary)
        func scaled(_ name: String, _ size: CGFloat, _ style: UIFont.TextStyle) -> UIFont? {
            UIFont(name: name, size: size).map { UIFontMetrics(forTextStyle: style).scaledFont(for: $0) }
        }
        let nav = UINavigationBar.appearance()
        if let font = scaled(Tokens.FontName.fredokaSemiBold, 17, .headline) {
            nav.titleTextAttributes = [.font: font, .foregroundColor: ink]
        }
        if let font = scaled(Tokens.FontName.fredokaSemiBold, 34, .largeTitle) {
            nav.largeTitleTextAttributes = [.font: font, .foregroundColor: ink]
        }
        if let font = scaled(Tokens.FontName.nunitoBold, 10, .caption2) {
            UITabBarItem.appearance().setTitleTextAttributes([.font: font], for: .normal)
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(tripStore)
                .environment(itemsStore)
                .environment(planStore)
                .environment(rulesStore)
        }
    }
}
