import SwiftUI

/// Accept destination packing suggestions into the item list (one tap).
struct SuggestionsView: View {
    @Environment(TripStore.self) private var tripStore
    @Environment(ItemsStore.self) private var itemsStore
    @Binding var path: [Route]

    private var open: [Suggestion] {
        tripStore.openSuggestions(excluding: itemsStore.items)
    }

    private var grouped: [(Category, [Suggestion])] {
        Dictionary(grouping: open, by: \.category)
            .map { ($0.key, $0.value) }
            .sorted { $0.0.rawValue < $1.0.rawValue }
    }

    var body: some View {
        Group {
            if tripStore.isLoadingSuggest {
                ProgressView(Copy.Trip.loadingSuggestions)
            } else if open.isEmpty {
                EmptyStateView(Copy.Trip.suggestionsEmpty, actionTitle: Copy.Trip.continueScan) {
                    path.append(.itemList)
                }
            } else {
                List {
                    if let err = tripStore.suggestError {
                        Section {
                            Text(err)
                                .font(Tokens.TypeScale.caption)
                                .foregroundStyle(Tokens.Color.restricted)
                        }
                    }
                    ForEach(grouped, id: \.0) { category, rows in
                        Section(category.rawValue.capitalized) {
                            ForEach(rows) { suggestion in
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
                                        HStack {
                                            Text(suggestion.name)
                                                .font(Tokens.TypeScale.body)
                                            if suggestion.essential {
                                                Text(Copy.Trip.essential)
                                                    .font(Tokens.TypeScale.caption)
                                                    .foregroundStyle(Tokens.Color.brand)
                                            }
                                        }
                                        Text(suggestion.reason)
                                            .font(Tokens.TypeScale.caption)
                                            .foregroundStyle(.secondary)
                                        Text(String(format: "%.0f×%.0f×%.0f cm · %.2f kg · estimated",
                                                   suggestion.estDims[safe: 0] ?? 0,
                                                   suggestion.estDims[safe: 1] ?? 0,
                                                   suggestion.estDims[safe: 2] ?? 0,
                                                   suggestion.estKg))
                                            .font(Tokens.TypeScale.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button(Copy.Trip.accept) {
                                        itemsStore.append(suggestion.asItem())
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(Tokens.Color.brand)
                                }
                            }
                        }
                    }
                }
            }
        }
        .packFitCanvas()
        .navigationTitle(Copy.Trip.suggestionsTitle)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(Copy.Trip.continueScan) { path.append(.itemList) }
            }
        }
    }
}

private extension Array where Element == Double {
    subscript(safe index: Int) -> Double? {
        indices.contains(index) ? self[index] : nil
    }
}
