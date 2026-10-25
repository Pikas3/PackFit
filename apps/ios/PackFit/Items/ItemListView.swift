import SwiftUI

struct ItemListView: View {
    @Environment(ItemsStore.self) private var itemsStore
    @Environment(TripStore.self) private var tripStore
    @Environment(PlanStore.self) private var planStore
    @Environment(RulesStore.self) private var rulesStore
    @Environment(AppNavigator.self) private var navigator
    @Binding var path: [Route]

    @State private var editing: Item?
    @State private var confirmItem: Item?
    @State private var showFlagSummary = false
    private let client = APIClientFactory.make()

    var body: some View {
        Group {
            if itemsStore.items.isEmpty {
                EmptyStateView(Copy.Items.empty, actionTitle: Copy.Items.emptyAction) {
                    path.append(.inventoryScan)
                }
            } else {
                List {
                    actions
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
                                IconBubble(
                                    systemImage: item.category.systemImage, size: 48, iconSize: 22,
                                    radius: Tokens.Radius.md, fill: item.category.swatch
                                )
                                VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
                                    Text(item.name)
                                        .font(Tokens.TypeScale.h3)
                                        .foregroundStyle(Tokens.Palette.textPrimary)
                                    Text(String(format: "%.1f×%.1f×%.1f cm · %.2f kg", item.w, item.h, item.d, item.kg))
                                        .font(Tokens.TypeScale.caption)
                                        .foregroundStyle(.secondary)
                                    HStack {
                                        MeasurementMethodBadge(method: item.measurement?.method)
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
                    .listRowBackground(Tokens.Palette.surface)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                NavTitle(title: Copy.Items.title, subtitle: itemsStore.items.isEmpty ? nil : Copy.Items.summary(
                    itemsStore.items.count, kg: itemsStore.items.reduce(0) { $0 + $1.kg }
                ))
            }
        }
        .packFitCanvas()
        .safeAreaInset(edge: .bottom) {
            if !itemsStore.items.isEmpty {
                optimizeButton
                    .padding(.horizontal, Tokens.Spacing.screen)
                    .padding(.bottom, Tokens.Spacing.sm)
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

    /// Scan more and packing ideas, as pills like the ones on Home.
    private var actions: some View {
        HStack(spacing: Tokens.Spacing.sm) {
            Button { path.append(.inventoryScan) } label: {
                PillLabel(title: Copy.Items.scanMore, systemImage: "camera.viewfinder")
            }
            if tripStore.trip != nil {
                Button { path.append(.suggestions) } label: {
                    PillLabel(title: Copy.Home.packingIdeas, systemImage: "sparkles")
                }
            }
        }
        // Without plain styles a List row fires every button in it on any tap.
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
        .listRowSeparator(.hidden)
    }

    /// Never a dead grey button: without a flight or a bag it says so and goes to set it up.
    @ViewBuilder
    private var optimizeButton: some View {
        if tripStore.trip == nil {
            Button { path.removeAll() } label: {
                Label(Copy.Items.needFlight, systemImage: "airplane")
            }
            .buttonStyle(.packFitPrimary)
        } else if tripStore.bag == nil {
            Button { path.append(.bagSetup) } label: {
                Label(Copy.Items.needBag, systemImage: "suitcase")
            }
            .buttonStyle(.packFitPrimary)
        } else {
            Button {
                Task { await packAndContinue() }
            } label: {
                HStack(spacing: Tokens.Spacing.sm) {
                    if planStore.isPacking {
                        ProgressView().tint(Tokens.Palette.pink800)
                    } else {
                        Image(systemName: "sparkles")
                    }
                    Text(Copy.Home.optimize)
                }
            }
            .buttonStyle(.packFitPrimary)
            .disabled(planStore.isPacking)
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
        await PackRun.run(
            trip: trip, bag: bag, useChecked: tripStore.useChecked, items: itemsStore.items,
            planStore: planStore, rulesStore: rulesStore, client: client
        )
        navigator.tab = .results
    }
}
