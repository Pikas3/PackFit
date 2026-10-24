import SwiftUI

struct ConfidenceBadge: View {
    let confidence: Double

    var body: some View {
        Text(label)
            .font(Tokens.TypeScale.caption)
            .padding(.horizontal, Tokens.Spacing.sm)
            .padding(.vertical, Tokens.Spacing.xs)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
            .accessibilityLabel(label)
    }

    private var label: String {
        if confidence >= 0.8 { return Copy.Scan.looksRight }
        if confidence >= 0.5 { return Copy.Scan.checkSize }
        return Copy.Scan.pleaseMeasure
    }

    private var color: Color {
        if confidence >= 0.8 { return .green }
        if confidence >= 0.5 { return .orange }
        return Tokens.Color.banned
    }
}

struct MeasurementMethodBadge: View {
    let method: MeasureMethod?
    var tapMeasured = false

    var body: some View {
        Text(text)
            .font(Tokens.TypeScale.caption)
            .padding(.horizontal, Tokens.Spacing.sm)
            .padding(.vertical, Tokens.Spacing.xs)
            .background(Tokens.Color.brandSecondary.opacity(0.2), in: Capsule())
    }

    private var text: String {
        if tapMeasured { return Copy.Scan.measuredARTaps }
        switch method {
        case .lidar: return Copy.Scan.measuredLidar
        case .manual: return Copy.Scan.measuredManual
        case .reference: return Copy.Scan.measuredReference
        case .estimate: return Copy.Scan.estimatedFromPhoto
        case .catalog: return "From catalog"
        case .none: return "Unknown"
        }
    }
}
