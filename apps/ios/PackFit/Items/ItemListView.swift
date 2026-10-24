import SwiftUI

struct ItemListView: View {
    @Environment(ItemsStore.self) private var itemsStore
    @Environment(TripStore.self) private var tripStore
    @Environment(PlanStore.self) private var planStore
    @Environment(RulesStore.self) private var rulesStore
    @Environment(DeviceCapabilities.self) private var caps
    @Binding var path: [Route]

    @State private var editing: Item?
    @State private var confirmItem: Item?
    @State private var showFlagSummary = false
    private let client = APIClientFactory.make()

    var body: some View {
        Group {
            if itemsStore.items.isEmpty {
                EmptyStateView(Copy.Items.empty, actionTitle: Copy.Items.emptyAction) {
                    path.append(.scan)
                }
            } else {
                List {
                    if !rulesStore.flags.isEmpty || rulesStore.stale {
                        Section {
                            Text(rulesStore.summary.isEmpty ? Copy.Items.flagsHint : rulesStore.summary)
                                .font(Tokens.TypeScale.caption)
                            Text(Copy.Rules.guidance)
                                .font(Tokens.TypeScale.caption)
                                .foregroundStyle(.secondary)
                            Button(Copy.Items.reviewFlags) { showFlagSummary = true }
                        }
                    }
                    ForEach(itemsStore.items) { item in
                        Button {
                            if (item.measurement?.confidence ?? item.confidence) < 0.6 {
                                confirmItem = item
                            } else {
                                editing = item
                            }
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
                                    let flags = rulesStore.flags(for: item.id)
                                    if !flags.isEmpty {
                                        HStack {
                                            Text(PackAdvice.forFlags(flags).rawValue)
                                                .font(Tokens.TypeScale.caption.weight(.semibold))
                                                .foregroundStyle(flagColor(flags))
                                            Text("· \(flags.count) flag\(flags.count == 1 ? "" : "s")")
                                                .font(Tokens.TypeScale.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .onDelete { offsets in
                        itemsStore.remove(at: offsets)
                        Task { await refreshFlags() }
                    }
                }
            }
        }
        .navigationTitle(Copy.Items.title)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(Copy.Trip.suggestionsTitle) { path.append(.suggestions) }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(Copy.Items.scan) { path.append(.scan) }
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
        .task(id: itemsStore.items.map(\.id)) {
            await refreshFlags()
        }
        .sheet(item: $editing) { item in
            ItemDetailView(item: item, flags: rulesStore.flags(for: item.id)) { updated in
                itemsStore.update(updated)
                editing = nil
                Task { await refreshFlags() }
            }
        }
        .sheet(item: $confirmItem) { item in
            NavigationStack {
                VStack(alignment: .leading, spacing: Tokens.Spacing.md) {
                    Text(Copy.Items.confirmIdentity)
                        .font(Tokens.TypeScale.title)
                    Text(item.name)
                        .font(Tokens.TypeScale.body)
                    Text(Copy.Items.confirmIdentityBody)
                        .font(Tokens.TypeScale.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(Copy.Items.confirmYes) {
                        confirmItem = nil
                        editing = item
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Tokens.Color.brand)
                    Button(Copy.Items.confirmEdit) {
                        confirmItem = nil
                        editing = item
                    }
                }
                .packFitScreenPadding()
                .navigationTitle(Copy.Items.confirmTitle)
                .navigationBarTitleDisplayMode(.inline)
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showFlagSummary) {
            NavigationStack {
                RulesView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(Copy.Trip.cancel) { showFlagSummary = false }
                        }
                    }
            }
        }
    }

    private func flagColor(_ flags: [RuleFlag]) -> Color {
        if flags.contains(where: { $0.severity == .banned }) { return Tokens.Color.banned }
        if flags.contains(where: { $0.severity == .restricted }) { return Tokens.Color.restricted }
        return Tokens.Color.brand
    }

    private func refreshFlags() async {
        guard let trip = tripStore.trip else { return }
        await rulesStore.check(
            items: itemsStore.items,
            trip: trip,
            bag: tripStore.useChecked ? "checked" : "carryOn",
            client: client
        )
    }

    private func packAndContinue() async {
        guard let bag = tripStore.bag, let trip = tripStore.trip else { return }
        // Drop banned items from the pack list after confirming advice.
        let bannedIds = Set(rulesStore.flags.filter { $0.severity == .banned }.map(\.itemId))
        let packable = itemsStore.items.filter { !bannedIds.contains($0.id) }
        await planStore.computePlan(items: packable, into: bag)
        await rulesStore.check(
            items: itemsStore.items,
            trip: trip,
            bag: tripStore.useChecked ? "checked" : "carryOn",
            client: client
        )
        path.append(.planViewer)
    }
}
