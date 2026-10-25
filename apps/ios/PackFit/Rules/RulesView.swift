import SwiftUI

/// Every flag for the trip as Figma flag cards, grouped by severity, with the stale banner.
struct RulesView: View {
    @Environment(RulesStore.self) private var rulesStore
    @Environment(ItemsStore.self) private var itemsStore
    @Environment(\.openURL) private var openURL

    private typealias P = Tokens.Palette
    private typealias T = Tokens.TypeScale

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Spacing.md) {
                if rulesStore.stale {
                    TipRow(text: Copy.Rules.stale)
                }
                if !rulesStore.summary.isEmpty {
                    Text(rulesStore.summary)
                        .font(T.body)
                        .foregroundStyle(P.textPrimary)
                }
                Text(Copy.Rules.guidance)
                    .font(T.caption)
                    .foregroundStyle(P.textSecondary)

                ForEach(RuleSeverity.allCases, id: \.self) { severity in
                    let group = rulesStore.flags.filter { $0.severity == severity }
                    if !group.isEmpty {
                        Text(severity.rawValue).eyebrow()
                            .padding(.top, Tokens.Spacing.sm)
                        ForEach(Array(group.enumerated()), id: \.offset) { _, flag in
                            let kind = FlagCard.Kind(flag.scope)
                            FlagCard(
                                kind: kind,
                                status: status(severity, kind: kind),
                                item: itemName(flag.itemId),
                                rule: flag.text,
                                fix: PackAdvice.forFlags([flag]).rawValue,
                                source: Copy.Flags.source(RuleFreshness.daysSinceVerified(flag.lastVerified)),
                                isStale: RuleFreshness.isStale(flag.lastVerified)
                            ) {
                                if let url = URL(string: flag.sourceUrl) { openURL(url) }
                            }
                        }
                    }
                }

                if rulesStore.flags.isEmpty {
                    VStack(spacing: Tokens.Spacing.md) {
                        IconBubble(systemImage: "checkmark.shield", size: 64, iconSize: 28, radius: Tokens.Radius.lg, fill: P.green100, tint: P.green700)
                        Text(Copy.Rules.empty)
                            .font(T.body)
                            .foregroundStyle(P.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, Tokens.Spacing.xl)
                }
            }
            .padding(.horizontal, Tokens.Spacing.screen)
            .padding(.vertical, Tokens.Spacing.sm)
        }
        .snuglyCanvas()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                NavTitle(title: Copy.Rules.title, subtitle: Copy.Results.flaggedCaption)
            }
        }
    }

    private func status(_ severity: RuleSeverity, kind: FlagCard.Kind) -> String {
        switch severity {
        case .banned: kind == .destination ? Copy.Flags.leaveHome : Copy.Flags.mustFix
        case .restricted: Copy.Flags.needsApproval
        case .check: Copy.Flags.checkFirst
        }
    }

    private func itemName(_ id: String) -> String {
        itemsStore.items.first(where: { $0.id == id })?.name ?? id
    }
}
