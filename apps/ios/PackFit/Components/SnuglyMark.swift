import SwiftUI

/// The Snugly suitcase from `docs/brand/snugly-mark.svg`, drawn natively so it stays sharp at
/// any size. Its face shows how the bag is doing. Fixed brand colours in both appearances.
struct SnuglyMark: View {
    enum Mood: Equatable {
        /// Nothing to pack yet.
        case sleepy
        /// Everything fits under the weight limit.
        case happy
        /// Over the weight limit, or the plan left something out.
        case worried
    }

    var mood: Mood = .happy
    var size: CGFloat = 44

    var body: some View {
        Canvas { context, canvas in
            // Crop of the 1024 artboard around the suitcase, tag and wheels.
            let crop = CGRect(x: 184, y: 190, width: 656, height: 656)
            let s = canvas.width / crop.width
            context.scaleBy(x: s, y: s)
            context.translateBy(x: -crop.minX, y: -crop.minY)
            Self.draw(mood, in: &context)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private static let plum = Color(hex: 0x8E2F55)
    private static let body = Color(hex: 0xC2577F)
    private static let ink = Color(hex: 0x4A2C3B)
    private static let blush = Color(hex: 0xFF9DBE)
    private static let tag = Color(hex: 0xFFD98A)
    private static let sweat = Color(hex: 0xCDBEFF)

    private static func draw(_ mood: Mood, in c: inout GraphicsContext) {
        let round = StrokeStyle(lineWidth: 16, lineCap: .round)

        c.stroke(
            Path(roundedRect: CGRect(x: 422, y: 214, width: 180, height: 140), cornerRadius: 60),
            with: .color(plum), lineWidth: 40
        )
        for x in [352.0, 672.0] {
            c.fill(Path(ellipseIn: CGRect(x: x - 28, y: 782, width: 56, height: 56)), with: .color(plum))
        }
        c.fill(
            Path(roundedRect: CGRect(x: 232, y: 314, width: 560, height: 490), cornerRadius: 150),
            with: .color(body)
        )

        switch mood {
        case .happy, .worried:
            for x in [432.0, 592.0] {
                c.fill(Path(ellipseIn: CGRect(x: x - 26, y: 514, width: 52, height: 52)), with: .color(ink))
                if mood == .happy {
                    c.fill(Path(ellipseIn: CGRect(x: x - 1, y: 522, width: 18, height: 18)), with: .color(.white))
                }
            }
        case .sleepy:
            for x in [432.0, 592.0] {
                var eye = Path()
                eye.move(to: CGPoint(x: x - 24, y: 534))
                eye.addQuadCurve(to: CGPoint(x: x + 24, y: 534), control: CGPoint(x: x, y: 560))
                c.stroke(eye, with: .color(ink), style: round)
            }
        }

        var mouth = Path()
        if mood == .worried {
            mouth.move(to: CGPoint(x: 486, y: 600))
            mouth.addQuadCurve(to: CGPoint(x: 538, y: 600), control: CGPoint(x: 512, y: 578))
        } else {
            mouth.move(to: CGPoint(x: 482, y: 584))
            mouth.addQuadCurve(to: CGPoint(x: 542, y: 584), control: CGPoint(x: 512, y: 614))
        }
        c.stroke(mouth, with: .color(ink), style: round)

        if mood == .worried {
            var drop = Path()
            drop.move(to: CGPoint(x: 330, y: 430))
            drop.addCurve(to: CGPoint(x: 330, y: 500), control1: CGPoint(x: 300, y: 470), control2: CGPoint(x: 300, y: 500))
            drop.addCurve(to: CGPoint(x: 330, y: 430), control1: CGPoint(x: 360, y: 500), control2: CGPoint(x: 360, y: 470))
            c.fill(drop, with: .color(sweat))
        } else {
            for x in [382.0, 642.0] {
                c.fill(Path(ellipseIn: CGRect(x: x - 30, y: 570, width: 60, height: 36)), with: .color(blush))
            }
        }

        var string = Path()
        string.move(to: CGPoint(x: 592, y: 300))
        string.addQuadCurve(to: CGPoint(x: 668, y: 392), control: CGPoint(x: 640, y: 330))
        c.stroke(string, with: .color(plum), style: StrokeStyle(lineWidth: 10, lineCap: .round))

        c.fill(heart(center: CGPoint(x: 690, y: 440), scale: 62), with: .color(tag))
    }

    private static func heart(center o: CGPoint, scale k: CGFloat) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: o.x + x * k, y: o.y + y * k) }
        var path = Path()
        path.move(to: p(0, 0.9))
        path.addCurve(to: p(0, -0.5), control1: p(-1.5, -0.1), control2: p(-0.95, -1.25))
        path.addCurve(to: p(0, 0.9), control1: p(0.95, -1.25), control2: p(1.5, -0.1))
        path.closeSubpath()
        return path
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

#Preview {
    HStack {
        SnuglyMark(mood: .sleepy, size: 120)
        SnuglyMark(mood: .happy, size: 120)
        SnuglyMark(mood: .worried, size: 120)
    }
}
