import SwiftUI

enum Tokens {
    enum Spacing {
        static let unit: CGFloat = 4
        static let xs: CGFloat = unit
        static let sm: CGFloat = unit * 2
        static let md: CGFloat = unit * 4
        static let lg: CGFloat = unit * 6
        static let xl: CGFloat = unit * 8
    }

    enum Radius {
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 20
    }

    enum Motion {
        static let stepSeconds: Double = 0.6
        static let quick: Double = 0.2
        static let standard: Double = 0.35
    }

    enum Color {
        static let brand = SwiftUI.Color("BrandPrimary")
        static let brandSecondary = SwiftUI.Color("BrandSecondary")
        static let surface = SwiftUI.Color("Surface")
        static let banned = SwiftUI.Color("SeverityBanned")
        static let restricted = SwiftUI.Color("SeverityRestricted")
        static let check = SwiftUI.Color("SeverityCheck")
    }

    enum TypeScale {
        static let hero: Font = .largeTitle.weight(.bold)
        static let title: Font = .title2.weight(.semibold)
        static let body: Font = .body
        static let caption: Font = .caption
        static let callout: Font = .callout
    }
}

extension View {
    func packFitScreenPadding() -> some View {
        padding(Tokens.Spacing.md)
    }
}
