import SwiftUI
import UIKit

/// Design tokens from the PackFit-Cute Figma file. Fredoka and Nunito are approximated with
/// SF Rounded so type stays on Dynamic Type text styles.
enum Tokens {
    enum Spacing {
        static let unit: CGFloat = 4
        static let xs: CGFloat = unit
        static let sm: CGFloat = unit * 2
        static let md: CGFloat = unit * 4
        static let lg: CGFloat = unit * 6
        static let xl: CGFloat = unit * 8
        /// Horizontal screen margin in the design.
        static let screen: CGFloat = 20
    }

    enum Radius {
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 20
        static let card: CGFloat = 24
        static let hero: CGFloat = 28
    }

    enum Motion {
        static let stepSeconds: Double = 0.6
        static let quick: Double = 0.2
        static let standard: Double = 0.35
    }

    /// Figma variables (`pink/300`, `text/primary`, ...) with dark-mode counterparts.
    enum Palette {
        static let canvas = dynamic(0xFFF6F9, 0x1C1217)
        static let surface = dynamic(0xFFFFFF, 0x2A1D24)
        static let textPrimary = dynamic(0x4A2C3B, 0xF7E9EF)
        static let textSecondary = dynamic(0x8F6E7E, 0xC9AEBB)

        static let pink100 = dynamic(0xFFE9F1, 0x3A2430)
        static let pink200 = dynamic(0xFFD3E2, 0x4D2C3C)
        static let pink300 = dynamic(0xFFB8CF, 0x8E3A5C)
        static let pink700 = dynamic(0xC2577F, 0xF49AB9)
        static let pink800 = dynamic(0x8E2F55, 0xFFE1EC)

        static let green100 = dynamic(0xE6F7ED, 0x173226)
        static let green200 = dynamic(0xC9EED8, 0x1F4A35)
        static let green400 = dynamic(0x9FDDBA, 0x3E8F66)
        static let green600 = dynamic(0x5DBB8A, 0x5DBB8A)
        static let green700 = dynamic(0x2E7D57, 0x8FDCB2)
        static let green800 = dynamic(0x1F5E40, 0xB5EBCC)

        static let coral100 = dynamic(0xFFE4DC, 0x40231C)
        static let coral500 = dynamic(0xD9674B, 0xFF9A80)
        static let amber100 = dynamic(0xFFF1D3, 0x3D2F12)
        static let amber500 = dynamic(0xB97F12, 0xF2B84B)
        static let lilac100 = dynamic(0xEEE7FF, 0x2B2445)
        static let lilac500 = dynamic(0x7B62C9, 0xB4A2F2)

        /// `Shadow/Soft Pink`: #F08CB0 at 14%, y 8, blur 24.
        static let shadow = dynamic(0xF08CB0, 0x000000, lightAlpha: 0.14, darkAlpha: 0.35)
        static let buttonShadow = dynamic(0xF0739E, 0x000000, lightAlpha: 0.28, darkAlpha: 0.35)

        private static func dynamic(
            _ light: UInt32, _ dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1
        ) -> SwiftUI.Color {
            SwiftUI.Color(UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor(hex: dark, alpha: darkAlpha)
                    : UIColor(hex: light, alpha: lightAlpha)
            })
        }
    }

    /// Older names, kept so every screen picks up the new palette.
    enum Color {
        static let brand = Palette.pink700
        static let brandSecondary = Palette.pink300
        static let surface = Palette.canvas
        static let banned = Palette.coral500
        static let restricted = Palette.amber500
        static let check = Palette.lilac500
    }

    /// Figma text styles mapped to the nearest Dynamic Type style.
    enum TypeScale {
        /// Display: Fredoka SemiBold 30.
        static let display: Font = .system(.title, design: .rounded, weight: .semibold)
        /// Heading/H1: Fredoka SemiBold 24.
        static let h1: Font = .system(.title2, design: .rounded, weight: .semibold)
        /// Heading/H2: Fredoka SemiBold 19.
        static let h2: Font = .system(.title3, design: .rounded, weight: .semibold)
        /// Heading/H3: Fredoka Medium 16.
        static let h3: Font = .system(.callout, design: .rounded, weight: .medium)
        /// Button: Fredoka SemiBold 17.
        static let button: Font = .system(.headline, design: .rounded, weight: .semibold)
        /// Body/Regular and Body/Bold: Nunito 14.
        static let body: Font = .system(.subheadline, design: .rounded)
        static let bodyBold: Font = .system(.subheadline, design: .rounded, weight: .bold)
        /// Caption: Nunito SemiBold 12.
        static let caption: Font = .system(.caption, design: .rounded, weight: .semibold)
        /// Label: Nunito ExtraBold 11, uppercase, tracked.
        static let label: Font = .system(.caption2, design: .rounded, weight: .heavy)
        static let labelTracking: CGFloat = 0.66

        static let hero: Font = display
        static let title: Font = h2
        static let callout: Font = body
    }
}

private extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

extension View {
    func packFitScreenPadding() -> some View {
        padding(Tokens.Spacing.md)
    }
}
