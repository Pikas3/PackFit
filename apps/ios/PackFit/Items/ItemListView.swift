import SwiftUI

struct ItemListView: View {
    @Environment(ItemsStore.self) private var itemsStore
    @Environment(TripStore.self) private var tripStore
    @Environment(PlanStore.self) private var planStore
    @Environment(RulesStore.self) private var rulesStore
    @Environment(DeviceCapabilities.self) private var caps
    @Binding var path: [Route]

    @State private var editing: Item?
    private let client = APIClientFactory.make()

    var body: some View {
        Group {
            if itemsStore.items.isEmpty {
                EmptyStateView(Copy.Items.empty, actionTitle: Copy.Items.emptyAction) {
                    path.append(.scan)
                }
            } else {
                List {
                    ForEach(itemsStore.items) { item in
                        Button {
                            editing = item
                        } label: {
                            HStack(spacing: Tokens.Spacing.md) {
                                RoundedRectangle(cornerRadius: Tokens.Radius.sm)
                                    .fill(Tokens.Color.brandSecondary.opacity(0.35))
                                    .frame(width: 48, height: 48)
                                    .overlay {
                                        Text(String(item.category.rawValue.prefix(1)).uppercased())
                                            .font(Tokens.TypeScale.title)
                                    }
                                VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
                                    Text(item.name)
                                        .font(Tokens.TypeScale.body)
                                        .foregroundStyle(.primary)
                                    Text(String(format: "%.1f×%.1f×%.1f cm · %.2f kg", item.w, item.h, item.d, item.kg))
                                        .font(Tokens.TypeScale.caption)
                                        .foregroundStyle(.secondary)
                                    HStack {
                                        MeasurementMethodBadge(method: item.measurement?.method, tapMeasured: itemsStore.tapMeasuredIDs.contains(item.id))
                                        ConfidenceBadge(confidence: item.measurement?.confidence ?? item.confidence)
                                    }
                                }
                            }
                        }
                    }
                    .onDelete { itemsStore.remove(at: $0) }
                }
            }
        }
        .navigationTitle(Copy.Items.title)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(Copy.Items.scan) { path.append(caps.supportsGuidedScan ? .guidedScan : .scan) }
            }
            ToolbarItem(placement: .bottomBar) {
                Button(Copy.Items.pack) {
                    Task { await packAndContinue() }
                }
                .buttonStyle(.borderedProminent)
                .tint(Tokens.Color.brand)
                .disabled(itemsStore.items.isEmpty || planStore.isPacking)
            }
        }
        .sheet(item: $editing) { item in
            ItemDetailView(item: item, flags: rulesStore.flags(for: item.id)) { updated in
                itemsStore.update(updated)
                editing = nil
            }
        }
    }

    private func packAndContinue() async {
        guard let bag = tripStore.bag, let trip = tripStore.trip else { return }
        await planStore.computePlan(items: itemsStore.items, into: bag)
        await rulesStore.check(
            items: itemsStore.items,
            trip: trip,
            bag: tripStore.useChecked ? "checked" : "carryOn",
            client: client
        )
        path.append(.planViewer)
    }
}
