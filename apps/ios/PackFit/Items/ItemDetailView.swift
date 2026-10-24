import SwiftUI

struct ItemDetailView: View {
    @State var item: Item
    let flags: [RuleFlag]
    var onSave: ((Item) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            Form {
                Section("Item") {
                    TextField("Name", text: $item.name)
                    Picker("Category", selection: $item.category) {
                        ForEach(Category.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    LabeledContent("Size") {
                        Text(String(format: "%.1f×%.1f×%.1f cm", item.w, item.h, item.d))
                    }
                    LabeledContent("Weight") {
                        Text(String(format: "%.2f kg", item.kg))
                    }
                    Toggle("Fragile", isOn: $item.fragile)
                    Toggle("Soft", isOn: $item.soft)
                }

                Section {
                    Text(Copy.Rules.guidance)
                        .font(Tokens.TypeScale.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Rules") {
                    if flags.isEmpty {
                        Text(Copy.Rules.empty)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(flags) { flag in
                            VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
                                Text(flag.severity.rawValue.uppercased())
                                    .font(Tokens.TypeScale.caption)
                                    .foregroundStyle(severityColor(flag.severity))
                                Text(flag.text)
                                Button("\(Copy.Rules.verifiedPrefix) \(RuleFreshness.daysSinceVerified(flag.lastVerified)) \(Copy.Rules.daysAgo)") {
                                    if let url = URL(string: flag.sourceUrl) {
                                        openURL(url)
                                    }
                                }
                                .font(Tokens.TypeScale.caption)
                            }
                        }
                    }
                }
            }
            .navigationTitle(item.name)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                if let onSave {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            onSave(item)
                            dismiss()
                        }
                    }
                }
            }
        }
    }

    private func severityColor(_ severity: RuleSeverity) -> Color {
        switch severity {
        case .banned: return Tokens.Color.banned
        case .restricted: return Tokens.Color.restricted
        case .check: return Tokens.Color.check
        }
    }
}
