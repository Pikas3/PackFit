import SwiftUI

struct RulesView: View {
    @Environment(RulesStore.self) private var rulesStore
    @Environment(ItemsStore.self) private var itemsStore
    @Environment(\.openURL) private var openURL

    var body: some View {
        List {
            if rulesStore.stale {
                Section {
                    Text(Copy.Rules.stale)
                        .font(Tokens.TypeScale.callout)
                        .foregroundStyle(Tokens.Color.restricted)
                }
            }
            if !rulesStore.summary.isEmpty {
                Section {
                    Text(rulesStore.summary)
                    Text(Copy.Rules.guidance)
                        .font(Tokens.TypeScale.caption)
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(RuleSeverity.allCases, id: \.self) { severity in
                let group = rulesStore.flags.filter { $0.severity == severity }
                if !group.isEmpty {
                    Section(severity.rawValue.capitalized) {
                        ForEach(group) { flag in
                            VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
                                Text(itemName(flag.itemId))
                                    .font(Tokens.TypeScale.body.weight(.semibold))
                                Text(flag.text)
                                Button {
                                    if let url = URL(string: flag.sourceUrl) { openURL(url) }
                                } label: {
                                    Text("Source · \(Copy.Rules.verifiedPrefix) \(RuleFreshness.daysSinceVerified(flag.lastVerified)) \(Copy.Rules.daysAgo)")
                                        .font(Tokens.TypeScale.caption)
                                }
                                if RuleFreshness.isStale(flag.lastVerified) {
                                    Text("Stale")
                                        .font(Tokens.TypeScale.caption)
                                        .foregroundStyle(Tokens.Color.restricted)
                                }
                            }
                        }
                    }
                }
            }
            if rulesStore.flags.isEmpty {
                Section { Text(Copy.Rules.empty).foregroundStyle(.secondary) }
            }
        }
        .navigationTitle(Copy.Rules.title)
    }

    private func itemName(_ id: String) -> String {
        itemsStore.items.first(where: { $0.id == id })?.name ?? id
    }
}
