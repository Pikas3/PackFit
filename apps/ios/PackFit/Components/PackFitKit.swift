import SwiftUI

// Shared UI components for Snugly. Colours and type come from `Tokens`.

private typealias P = Tokens.Palette
private typealias T = Tokens.TypeScale

// MARK: - Surfaces

extension View {
    /// White card with the soft pink shadow.
    func cardStyle(
        padding: CGFloat = Tokens.Spacing.md,
        radius: CGFloat = Tokens.Radius.card,
        fill: Color = Tokens.Palette.surface,
        stroke: Color? = nil,
        shadow: Bool = true
    ) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                if let stroke {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(stroke, lineWidth: 1.5)
                }
            }
            .shadow(color: shadow ? Tokens.Palette.shadow : .clear, radius: 12, y: 8)
    }

    /// Canvas colour with the pink and green blobs behind the content.
    func packFitCanvas() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background { BlobBackground().ignoresSafeArea() }
    }

    /// Uppercase tracked label style (`Label` text style).
    func eyebrow(_ color: Color = Tokens.Palette.textSecondary) -> some View {
        self
            .font(T.label)
            .tracking(T.labelTracking)
            .textCase(.uppercase)
            .foregroundStyle(color)
    }
}

/// `Decor/Blob Pink` and `Decor/Blob Green`: soft blurred shapes on the canvas.
struct BlobBackground: View {
    var body: some View {
        P.canvas
            .overlay(alignment: .topTrailing) {
                Circle()
                    .fill(P.pink200.opacity(0.9))
                    .frame(width: 260, height: 260)
                    .blur(radius: 60)
                    .offset(x: 70, y: -90)
            }
            .overlay(alignment: .topLeading) {
                Circle()
                    .fill(P.green200.opacity(0.8))
                    .frame(width: 200, height: 200)
                    .blur(radius: 60)
                    .offset(x: -90, y: 300)
            }
            .accessibilityHidden(true)
    }
}

// MARK: - Buttons

/// `Button/Primary`: full-width pink pill with an optional leading icon.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(T.button)
            .foregroundStyle(P.pink800)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Tokens.Spacing.lg)
            .padding(.vertical, 18)
            .background(P.pink300, in: RoundedRectangle(cornerRadius: Tokens.Radius.hero, style: .continuous))
            .shadow(color: P.buttonShadow, radius: 10, y: 8)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(isEnabled ? 1 : 0.5)
            .animation(.easeOut(duration: Tokens.Motion.quick), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var packFitPrimary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

/// Small pink pill action, like "Add photo" on the bag tile.
struct PillLabel: View {
    let title: String
    var systemImage: String?

    var body: some View {
        HStack(spacing: Tokens.Spacing.xs) {
            if let systemImage {
                Image(systemName: systemImage).font(.caption2.weight(.bold))
            }
            Text(title)
        }
        .font(T.caption)
        .foregroundStyle(P.pink700)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(P.pink100, in: Capsule())
    }
}

// MARK: - Chips

/// `Chip` with Default, Selected and Complete states.
struct Chip: View {
    /// `plain` is the borderless option inside a segmented switcher.
    enum State { case normal, selected, complete, plain }

    let label: String
    var state: State = .normal

    var body: some View {
        HStack(spacing: Tokens.Spacing.xs) {
            if state == .complete {
                Image(systemName: "checkmark").font(.caption2.weight(.bold))
            }
            Text(label)
                .lineLimit(1)
        }
        .font(T.caption)
        .foregroundStyle(foreground)
        .padding(.leading, state == .complete ? 10 : 14)
        .padding(.trailing, 14)
        .padding(.vertical, 8)
        .background(background, in: Capsule())
        .overlay {
            if let border { Capsule().strokeBorder(border, lineWidth: 1.5) }
        }
        .accessibilityAddTraits(state == .selected ? .isSelected : [])
    }

    private var foreground: Color {
        switch state {
        case .normal, .plain: P.textSecondary
        case .selected: P.pink800
        case .complete: P.green700
        }
    }

    private var background: Color {
        switch state {
        case .normal, .plain: P.surface
        case .selected: P.pink300
        case .complete: P.green100
        }
    }

    private var border: Color? {
        switch state {
        case .normal: P.pink200
        case .selected, .plain: nil
        case .complete: P.green400
        }
    }
}

/// Wraps chips onto as many rows as they need.
struct FlowLayout: Layout {
    var spacing: CGFloat = Tokens.Spacing.sm

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row { var indices: [Int] = []; var y: CGFloat = 0; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !row.indices.isEmpty, row.width + spacing + size.width > width {
                rows.append(row)
                row = Row(y: row.y + row.height + spacing)
            }
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}

// MARK: - Headers and small composites

/// Rounded square holding one SF Symbol.
struct IconBubble: View {
    let systemImage: String
    var size: CGFloat = 40
    var iconSize: CGFloat = 20
    var radius: CGFloat = 14
    var fill: Color = Tokens.Palette.pink100
    var tint: Color = Tokens.Palette.pink700

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: iconSize, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// `Section Header`: number badge, title and caption.
struct SectionHeader: View {
    enum Tone { case pink, green }

    var number: String?
    var systemImage: String?
    let title: String
    var caption: String?
    var tone: Tone = .pink

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 17, weight: .semibold))
                } else {
                    Text(number ?? "").font(T.h3)
                }
            }
            .foregroundStyle(tone == .green ? P.green800 : P.pink800)
            .frame(width: 32, height: 32)
            .background(tone == .green ? P.green200 : P.pink200, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(T.h2)
                    .foregroundStyle(P.textPrimary)
                if let caption {
                    Text(caption)
                        .font(T.caption)
                        .foregroundStyle(P.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// `Stat Tile`: big number over a caption.
struct StatTile: View {
    let value: String
    let label: String
    var valueColor: Color = Tokens.Palette.textPrimary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(T.h1)
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(T.caption)
                .foregroundStyle(P.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .cardStyle(padding: 14, radius: Tokens.Radius.lg)
        .accessibilityElement(children: .combine)
    }
}

/// `Itinerary Field`: icon bubble, label over value, chevron.
struct ItineraryField: View {
    let systemImage: String
    let label: String
    let value: String
    var isPlaceholder = false

    var body: some View {
        HStack(spacing: 12) {
            IconBubble(systemImage: systemImage)
            VStack(alignment: .leading, spacing: 1) {
                Text(label).eyebrow()
                Text(value)
                    .font(T.bodyBold)
                    .foregroundStyle(isPlaceholder ? P.textSecondary : P.textPrimary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(P.textSecondary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// `Tip` row with a lightbulb.
struct TipRow: View {
    let text: String

    var body: some View {
        HStack(spacing: Tokens.Spacing.sm) {
            Image(systemName: "lightbulb")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(P.pink700)
                .accessibilityHidden(true)
            Text(text)
                .font(T.caption)
                .foregroundStyle(P.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(P.surface, in: RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous).strokeBorder(P.pink100, lineWidth: 1)
        }
    }
}

/// Toolbar title with a subtitle, like the Figma nav header.
struct NavTitle: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(spacing: 0) {
            Text(title).font(T.h2).foregroundStyle(P.textPrimary)
            if let subtitle {
                Text(subtitle).font(T.caption).foregroundStyle(P.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Flag card

/// `Flag Card` in its TSA, Airline and Destination variants.
struct FlagCard: View {
    enum Kind {
        case tsa, airline, destination

        init(_ scope: RuleScope) {
            switch scope {
            case .tsa: self = .tsa
            case .airline: self = .airline
            case .country: self = .destination
            }
        }

        var badge: String {
            switch self {
            case .tsa: Copy.Flags.tsaBadge
            case .airline: Copy.Flags.airlineBadge
            case .destination: Copy.Flags.destinationBadge
            }
        }

        var systemImage: String {
            switch self {
            case .tsa: "exclamationmark.shield"
            case .airline: "airplane"
            case .destination: "globe"
            }
        }

        var soft: Color {
            switch self {
            case .tsa: P.coral100
            case .airline: P.amber100
            case .destination: P.lilac100
            }
        }

        var strong: Color {
            switch self {
            case .tsa: P.coral500
            case .airline: P.amber500
            case .destination: P.lilac500
            }
        }
    }

    let kind: Kind
    let status: String
    let item: String
    let rule: String
    var fix: String?
    var source: String?
    var isStale = false
    var onSource: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            IconBubble(systemImage: kind.systemImage, size: 44, iconSize: 22, radius: 16, fill: kind.soft, tint: kind.strong)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(kind.badge)
                        .eyebrow(kind.strong)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(kind.soft, in: Capsule())
                    Spacer(minLength: Tokens.Spacing.sm)
                    Text(status)
                        .font(T.caption)
                        .foregroundStyle(kind.strong)
                }
                Text(item)
                    .font(T.h3)
                    .foregroundStyle(P.textPrimary)
                Text(rule)
                    .font(T.body)
                    .foregroundStyle(P.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let fix {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "sparkles").font(.system(size: 12, weight: .semibold))
                        Text(fix)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(T.caption)
                    .foregroundStyle(P.pink800)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(P.pink100, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                if let source {
                    Button {
                        onSource?()
                    } label: {
                        HStack(spacing: Tokens.Spacing.xs) {
                            Image(systemName: "link")
                            Text(source)
                            if isStale {
                                Text(Copy.Flags.stale)
                                    .foregroundStyle(P.amber500)
                            }
                        }
                        .font(T.caption)
                        .foregroundStyle(P.pink700)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .cardStyle(radius: 22, stroke: kind.soft)
    }
}

// MARK: - Checklist row

/// `Checklist Item` in Todo and Done states.
struct ChecklistRow: View {
    let step: String
    let title: String
    let detail: String
    let zone: String
    let done: Bool

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(done ? P.green400 : P.surface)
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(done ? .clear : P.pink300, lineWidth: 2)
                if done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(P.green800)
                }
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(step).eyebrow(done ? P.green700 : P.pink700)
                Text(title)
                    .font(T.bodyBold)
                    .foregroundStyle(done ? P.textSecondary : P.textPrimary)
                    .strikethrough(done, color: P.textSecondary.opacity(0.5))
                Text(detail)
                    .font(T.caption)
                    .foregroundStyle(P.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(zone)
                .font(T.caption)
                .foregroundStyle(done ? P.green700 : P.pink700)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(done ? P.green100 : P.pink100, in: Capsule())
        }
        .cardStyle(padding: 14, radius: Tokens.Radius.lg, stroke: done ? P.green200 : P.pink100, shadow: false)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(done ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Category icons

extension Category {
    /// SF Symbol for item thumbnails and checklist bubbles.
    var systemImage: String {
        switch self {
        case .clothing: "tshirt"
        case .shoes: "shoeprints.fill"
        case .toiletries: "comb"
        case .liquids: "drop"
        case .electronics: "bolt"
        case .documents: "doc.text"
        case .medical: "cross.case"
        case .food: "fork.knife"
        case .sharp: "scissors"
        case .other: "shippingbox"
        }
    }

    /// Thumbnail fill, cycling the pink and green swatches from the upload tile.
    var swatch: Color {
        switch self {
        case .clothing, .documents, .sharp: P.pink200
        case .shoes, .electronics, .other: P.pink300
        case .toiletries, .liquids, .medical, .food: P.green200
        }
    }
}
