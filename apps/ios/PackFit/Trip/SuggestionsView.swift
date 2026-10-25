import SwiftUI

/// Accept destination packing suggestions into the item list. Repeats of one thing
/// ("T-shirt stack (1)", "(2)", ...) collapse into one card with a count to add.
struct SuggestionsView: View {
    @Environment(TripStore.self) private var tripStore
    @Environment(ItemsStore.self) private var itemsStore
    @Binding var path: [Route]

    /// How many of each group to add, keyed by `SuggestionGroup.id`. Missing means all.
    @State private var picks: [String: Int] = [:]

    private typealias P = Tokens.Palette
    private typealias T = Tokens.TypeScale

    private var open: [Suggestion] {
        tripStore.openSuggestions(excluding: itemsStore.items)
    }

    private var grouped: [(Category, [SuggestionGroup])] {
        Dictionary(grouping: SuggestionGroup.group(open), by: \.category)
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
                ScrollView {
                    VStack(alignment: .leading, spacing: Tokens.Spacing.md) {
                        if let err = tripStore.suggestError {
                            TipRow(text: err)
                        }
                        ForEach(grouped, id: \.0) { category, groups in
                            Text(category.rawValue).eyebrow()
                                .padding(.top, Tokens.Spacing.sm)
                            ForEach(groups) { group in
                                card(group)
                            }
                        }
                    }
                    .padding(.horizontal, Tokens.Spacing.screen)
                    .padding(.vertical, Tokens.Spacing.sm)
                }
            }
        }
        .snuglyCanvas()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                NavTitle(title: Copy.Trip.suggestionsTitle, subtitle: Copy.Trip.suggestionsCaption(SuggestionGroup.group(open).count))
            }
            // The pill is the button's whole look, so drop iOS 26's glass capsule around it.
            if #available(iOS 26, *) {
                ToolbarItem(placement: .confirmationAction) { scanButton }
                    .sharedBackgroundVisibility(.hidden)
            } else {
                ToolbarItem(placement: .confirmationAction) { scanButton }
            }
        }
    }

    private var scanButton: some View {
        Button { path.append(.itemList) } label: {
            PillLabel(title: Copy.Trip.continueScan, systemImage: "camera.viewfinder")
        }
        .buttonStyle(.plain)
    }

    private func card(_ group: SuggestionGroup) -> some View {
        let count = min(picks[group.id] ?? group.count, group.count)
        let first = group.members[0]
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                IconBubble(systemImage: group.category.systemImage, size: 44, iconSize: 20, radius: 16, fill: group.category.swatch)
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.name)
                        .font(T.h3)
                        .foregroundStyle(P.textPrimary)
                    if group.count > 1 || group.essential {
                        HStack(spacing: 6) {
                            if group.count > 1 {
                                Text("×\(group.count)")
                                    .font(T.caption)
                                    .foregroundStyle(P.pink800)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(P.pink200, in: Capsule())
                            }
                            if group.essential {
                                Text(Copy.Trip.essential)
                                    .eyebrow(P.green700)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(P.green100, in: Capsule())
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    Text(first.reason)
                        .font(T.caption)
                        .foregroundStyle(P.textSecondary)
                    Text(Copy.Trip.suggestionSize(dims: first.estDims, kg: first.estKg, count: group.count))
                        .font(T.caption)
                        .foregroundStyle(P.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if group.count == 1 {
                    Button {
                        itemsStore.append(first.asItem())
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(P.pink800)
                            .frame(width: 44, height: 44)
                            .background(P.pink300, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(Copy.Trip.accept) \(group.name)")
                }
            }

            // Only repeated suggestions need a count; single ones add from the top row.
            if group.count > 1 {
                HStack(spacing: Tokens.Spacing.sm) {
                    countPicker(group: group, count: count)
                    Spacer()
                    addButton(group, count: count)
                }
            }
        }
        .cardStyle(radius: 22)
    }

    private func addButton(_ group: SuggestionGroup, count: Int) -> some View {
        Button {
            for suggestion in group.members.prefix(count) {
                itemsStore.append(suggestion.asItem())
            }
            picks[group.id] = nil
        } label: {
            Label(Copy.Trip.addCount(count), systemImage: "plus")
                .font(T.button)
                .foregroundStyle(P.pink800)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(P.pink300, in: Capsule())
                .fixedSize()
        }
        .buttonStyle(.plain)
        .disabled(count == 0)
    }

    /// Minus, count, plus, between 1 and the number suggested.
    private func countPicker(group: SuggestionGroup, count: Int) -> some View {
        HStack(spacing: 0) {
            stepButton("minus", enabled: count > 1) { picks[group.id] = count - 1 }
            Text("\(count)")
                .font(T.bodyBold)
                .foregroundStyle(P.textPrimary)
                .monospacedDigit()
                .frame(minWidth: 28)
            stepButton("plus", enabled: count < group.count) { picks[group.id] = count + 1 }
        }
        .padding(4)
        .background(P.pink100, in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Copy.Trip.howMany(group.name))
        .accessibilityValue("\(count)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: picks[group.id] = min(count + 1, group.count)
            case .decrement: picks[group.id] = max(count - 1, 1)
            @unknown default: break
            }
        }
    }

    private func stepButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(P.pink700)
                .frame(width: 30, height: 30)
                .background(P.surface, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }
}

/// Suggestions that are the same thing, told apart only by a "(n)" suffix or letter case.
struct SuggestionGroup: Identifiable {
    let id: String
    let name: String
    let category: Category
    let members: [Suggestion]

    var count: Int { members.count }
    var essential: Bool { members.contains { $0.essential } }

    /// Groups in first-seen order, so the list doesn't reshuffle as items are added.
    static func group(_ suggestions: [Suggestion]) -> [SuggestionGroup] {
        var order: [String] = []
        var buckets: [String: [Suggestion]] = [:]
        for suggestion in suggestions {
            let key = "\(suggestion.category.rawValue)|\(baseName(suggestion.name).lowercased())"
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(suggestion)
        }
        return order.compactMap { key in
            guard let members = buckets[key], let first = members.first else { return nil }
            return SuggestionGroup(id: key, name: baseName(first.name), category: first.category, members: members)
        }
    }

    /// "T-shirt stack (3)" becomes "T-shirt stack".
    static func baseName(_ name: String) -> String {
        name.replacingOccurrences(of: #"\s*\(\d+\)\s*$"#, with: "", options: .regularExpression)
    }
}
