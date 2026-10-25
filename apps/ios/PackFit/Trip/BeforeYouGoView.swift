import SwiftUI

/// Country-specific pack / leave / declare tips with source links.
struct BeforeYouGoView: View {
    @Environment(TripStore.self) private var tripStore
    @Environment(ItemsStore.self) private var itemsStore
    @Environment(RulesStore.self) private var rulesStore
    @Environment(\.openURL) private var openURL

    var body: some View {
        List {
            Section {
                Text(Copy.Rules.guidance)
                    .font(Tokens.TypeScale.caption)
                    .foregroundStyle(.secondary)
                if let country = tripStore.destinationCountry {
                    Text(Copy.Trip.destinationCountry(country))
                        .font(Tokens.TypeScale.callout)
                }
            }

            if let panel = tripStore.beforeYouGo {
                tipSection(Copy.Trip.packThese, tips: panel.pack)
                tipSection(Copy.Trip.leaveOrDeclare, tips: panel.leaveOrDeclare)
                tipSection(Copy.Trip.medsFood, tips: panel.medicationFood)
            } else {
                Section { Text(Copy.Trip.beforeYouGoEmpty).foregroundStyle(.secondary) }
            }

            let countryFlags = rulesStore.flags.filter { $0.scope == .country }
            if !countryFlags.isEmpty {
                Section(Copy.Trip.packedWarnings) {
                    ForEach(countryFlags) { flag in
                        VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
                            Text(itemName(flag.itemId))
                                .font(Tokens.TypeScale.body.weight(.semibold))
                            Text(flag.text)
                            Button {
                                if let url = URL(string: flag.sourceUrl) { openURL(url) }
                            } label: {
                                Text(Copy.Trip.sourceLink)
                                    .font(Tokens.TypeScale.caption)
                            }
                        }
                    }
                }
            }

            ForEach(tripStore.warnings.filter {
                if case .overweight = $0 { return true }
                return false
            }, id: \.plainLanguage) { warning in
                Section(Copy.Trip.weightWarning) {
                    Text(warning.plainLanguage)
                        .foregroundStyle(Tokens.Color.restricted)
                }
            }
        }
        .packFitCanvas()
        .navigationTitle(Copy.Trip.beforeYouGoTitle)
    }

    @ViewBuilder
    private func tipSection(_ title: String, tips: [BeforeYouGoTip]) -> some View {
        if !tips.isEmpty {
            Section(title) {
                ForEach(tips) { tip in
                    VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
                        Text(tip.text)
                        Button {
                            if let url = URL(string: tip.sourceUrl) { openURL(url) }
                        } label: {
                            Text("\(Copy.Trip.sourceLink) · \(Copy.Rules.verifiedPrefix) \(RuleFreshness.daysSinceVerified(tip.lastVerified)) \(Copy.Rules.daysAgo)")
                                .font(Tokens.TypeScale.caption)
                        }
                    }
                }
            }
        }
    }

    private func itemName(_ id: String) -> String {
        itemsStore.items.first(where: { $0.id == id })?.name ?? id
    }
}
