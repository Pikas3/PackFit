import SwiftUI
import Packer
import RealityKit

/// Results tab (Figma "02 · Results"): the 3D plan, stats, rule flags and what didn't fit.
struct PlanViewerView: View {
    @Environment(PlanStore.self) private var planStore
    @Environment(ItemsStore.self) private var itemsStore
    @Environment(TripStore.self) private var tripStore
    @Environment(RulesStore.self) private var rulesStore
    @Environment(AppNavigator.self) private var navigator
    @Environment(\.openURL) private var openURL
    @Binding var path: [Route]

    @State private var controller = PlanViewerController()
    @State private var selectedItem: Item?
    @State private var dragStart: SIMD2<Float>?
    @State private var viewMode = 0
    @State private var layer = 0
    @State private var flagFilter: FlagCard.Kind?

    private let client = APIClientFactory.make()

    private typealias P = Tokens.Palette
    private typealias T = Tokens.TypeScale

    var body: some View {
        Group {
            if planStore.plan == nil && !planStore.isPacking {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Tokens.Spacing.lg) {
                        vizCard
                        statsRow
                        flagsSection
                        leftOutCard
                        Button { navigator.tab = .plan } label: {
                            Label(Copy.Results.seePlan, systemImage: "checklist")
                        }
                        .buttonStyle(.snuglyPrimary)
                        .disabled(planStore.plan == nil)
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
                NavTitle(title: Copy.Results.title, subtitle: routeLabel)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(Copy.Results.repack, systemImage: "arrow.triangle.2.circlepath") {
                    Task { await repack() }
                }
                .disabled(tripStore.trip == nil || tripStore.bag == nil || planStore.isPacking)
            }
        }
        .sheet(item: $selectedItem) { item in
            ItemDetailView(item: item, flags: rulesStore.flags(for: item.id))
        }
        .task {
            if planStore.plan == nil, let bag = tripStore.bag, !itemsStore.items.isEmpty {
                await planStore.computePlan(items: itemsStore.items, into: bag)
            }
            reloadScene()
        }
        .onChange(of: planStore.plan) { _, _ in reloadScene() }
    }

    private var emptyState: some View {
        VStack(spacing: Tokens.Spacing.md) {
            IconBubble(systemImage: "shippingbox", size: 72, iconSize: 32, radius: Tokens.Radius.card, fill: P.pink100)
            Text(Copy.Results.empty)
                .font(T.body)
                .foregroundStyle(P.textSecondary)
                .multilineTextAlignment(.center)
            Button { navigator.tab = .home } label: {
                Label(Copy.Results.goHome, systemImage: "house")
            }
            .buttonStyle(.snuglyPrimary)
        }
        .padding(Tokens.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: 3D card

    private var vizCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            reality
                .frame(height: 300)
                .background(P.pink100)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(alignment: .topLeading) {
                    Label(Copy.Results.rotateHint, systemImage: "arrow.triangle.2.circlepath")
                        .font(T.caption)
                        .foregroundStyle(P.pink700)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(P.surface, in: Capsule())
                        .padding(12)
                        .allowsHitTesting(false)
                }
                .overlay(alignment: .topTrailing) {
                    if let stats = planStore.plan?.stats {
                        Label(Copy.Results.full(stats.fillPct), systemImage: "checkmark")
                            .font(T.caption)
                            .foregroundStyle(P.pink800)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(P.pink300, in: Capsule())
                            .padding(12)
                            .allowsHitTesting(false)
                    }
                }
                .overlay(alignment: .bottom) { viewSwitcher.padding(.bottom, 12) }
                .overlay {
                    if planStore.isPacking { ProgressView().tint(P.pink700) }
                }

            layerFilter
            PlanStepControls(stepper: controller.stepper)
                .padding(.horizontal, Tokens.Spacing.xs)
        }
        .cardStyle(padding: 12, radius: Tokens.Radius.hero)
    }

    private var reality: some View {
        RealityView { content in
            content.add(controller.root)
            content.add(controller.cameraPivot)
            let light = DirectionalLight()
            light.light.intensity = 1200
            light.shadow = nil
            light.look(at: .zero, from: [1, 2, 1], relativeTo: nil)
            content.add(light)
        } update: { _ in
            controller.updateCameraTransform()
        }
        .gesture(orbitGesture)
        .gesture(magnifyGesture)
        .simultaneousGesture(tapGesture)
    }

    private var viewSwitcher: some View {
        HStack(spacing: Tokens.Spacing.xs) {
            ForEach(Array(Copy.Results.views.enumerated()), id: \.offset) { index, name in
                Button {
                    viewMode = index
                    applyViewMode()
                } label: {
                    Chip(label: name, state: viewMode == index ? .selected : .plain)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Tokens.Spacing.xs)
        .background(P.surface, in: Capsule())
    }

    private var layerFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Tokens.Spacing.sm) {
                Text(Copy.Results.layers).eyebrow()
                ForEach(Array(Copy.Results.layerNames.enumerated()), id: \.offset) { index, name in
                    Button {
                        layer = index
                        applyLayer()
                    } label: {
                        Chip(label: name, state: layer == index ? .selected : .normal)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.leading, Tokens.Spacing.xs)
        }
    }

    // MARK: Stats

    @ViewBuilder
    private var statsRow: some View {
        if let plan = planStore.plan {
            let total = plan.placed.count + plan.unplaced.count
            HStack(spacing: 10) {
                StatTile(value: String(format: "%.0f%%", plan.stats.fillPct), label: Copy.Results.spaceUsed)
                let limitKg = tripStore.bag?.weightLimitKg ?? 23
                StatTile(
                    value: String(format: "%.1f kg", plan.stats.kg),
                    label: Copy.Results.ofLimit(limitKg),
                    valueColor: plan.stats.kg > limitKg ? P.coral500 : P.textPrimary
                )
                StatTile(value: "\(plan.placed.count)/\(total)", label: Copy.Results.itemsFit)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Flags

    private struct FlagEntry: Identifiable {
        let id: String
        let kind: FlagCard.Kind
        let status: String
        let item: String
        let rule: String
        let fix: String?
        let source: String
        let stale: Bool
        let url: String
    }

    private var flagEntries: [FlagEntry] {
        let fromFlags = rulesStore.flags.enumerated().map { index, flag in
            let kind = FlagCard.Kind(flag.scope)
            return FlagEntry(
                id: "flag-\(index)",
                kind: kind,
                status: status(flag.severity, kind: kind),
                item: itemName(flag.itemId),
                rule: flag.text,
                fix: PackAdvice.forFlags([flag]).rawValue,
                source: Copy.Flags.source(RuleFreshness.daysSinceVerified(flag.lastVerified)),
                stale: RuleFreshness.isStale(flag.lastVerified),
                url: flag.sourceUrl
            )
        }
        // A customs tip already shown as an item flag is not repeated as a route card.
        let flaggedSources = Set(rulesStore.flags.map(\.sourceUrl))
        let fromRoute = tripStore.routeNotices.filter { !flaggedSources.contains($0.sourceUrl) }.map { notice in
            let kind: FlagCard.Kind = switch notice.scope.lowercased() {
            case "tsa": .tsa
            case "airline": .airline
            default: .destination
            }
            return FlagEntry(
                id: "route-\(notice.id)",
                kind: kind,
                status: Copy.Flags.checkFirst,
                item: Copy.Results.routeItem,
                rule: notice.text,
                fix: nil,
                source: Copy.Flags.source(RuleFreshness.daysSinceVerified(notice.lastVerified)),
                stale: RuleFreshness.isStale(notice.lastVerified),
                url: notice.sourceUrl
            )
        }
        return fromFlags + fromRoute
    }

    @ViewBuilder
    private var flagsSection: some View {
        let entries = flagEntries
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    IconBubble(systemImage: "exclamationmark.triangle", size: 36, iconSize: 18, radius: 12, fill: P.coral100, tint: P.coral500)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(Copy.Results.flagged(rulesStore.flags.count))
                            .font(T.h2)
                            .foregroundStyle(P.textPrimary)
                        Text(Copy.Results.flaggedCaption)
                            .font(T.caption)
                            .foregroundStyle(P.textSecondary)
                    }
                    Spacer()
                    Button(Copy.Results.allRules) { path.append(.rules) }
                        .font(T.caption)
                }
                .accessibilityAddTraits(.isHeader)

                FlowLayout {
                    filterChip(nil, Copy.Results.filterAll, entries.count)
                    filterChip(.tsa, Copy.Results.filterTSA, entries.filter { $0.kind == .tsa }.count)
                    filterChip(.airline, Copy.Results.filterAirline, entries.filter { $0.kind == .airline }.count)
                    filterChip(.destination, Copy.Results.filterDestination, entries.filter { $0.kind == .destination }.count)
                }

                if rulesStore.stale {
                    TipRow(text: Copy.Rules.stale)
                }

                ForEach(entries.filter { flagFilter == nil || $0.kind == flagFilter }) { entry in
                    FlagCard(
                        kind: entry.kind, status: entry.status, item: entry.item, rule: entry.rule,
                        fix: entry.fix, source: entry.source, isStale: entry.stale
                    ) {
                        if let url = URL(string: entry.url) { openURL(url) }
                    }
                }

                Text(Copy.Rules.guidance)
                    .font(T.caption)
                    .foregroundStyle(P.textSecondary)
            }
        }
    }

    private func filterChip(_ kind: FlagCard.Kind?, _ name: String, _ count: Int) -> some View {
        Button { flagFilter = kind } label: {
            Chip(label: "\(name) · \(count)", state: flagFilter == kind ? .selected : .normal)
        }
        .buttonStyle(.plain)
    }

    private func status(_ severity: RuleSeverity, kind: FlagCard.Kind) -> String {
        switch severity {
        case .banned: kind == .destination ? Copy.Flags.leaveHome : Copy.Flags.mustFix
        case .restricted: Copy.Flags.needsApproval
        case .check: Copy.Flags.checkFirst
        }
    }

    // MARK: Left out

    @ViewBuilder
    private var leftOutCard: some View {
        if let unplaced = planStore.plan?.unplaced, !unplaced.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    IconBubble(systemImage: "shippingbox", size: 36, iconSize: 18, radius: 12, fill: P.surface)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(Copy.Results.leftOut(unplaced.count))
                            .font(T.h3)
                            .foregroundStyle(P.textPrimary)
                        Text(Copy.Results.leftOutCaption)
                            .font(T.caption)
                            .foregroundStyle(P.textSecondary)
                    }
                }
                FlowLayout {
                    ForEach(Array(unplaced.enumerated()), id: \.offset) { _, id in
                        let item = itemsStore.items.first { $0.id == id }
                        Button { selectedItem = item } label: {
                            Chip(label: "\(item?.name ?? id): \(shortReason(planStore.unplacedReasons[id]))")
                        }
                        .buttonStyle(.plain)
                        .disabled(item == nil)
                        .accessibilityHint(reasonText(planStore.unplacedReasons[id]))
                    }
                }
                if let first = unplaced.first {
                    Text(reasonText(planStore.unplacedReasons[first]))
                        .font(T.caption)
                        .foregroundStyle(P.textSecondary)
                }
            }
            .padding(Tokens.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(P.pink100, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }

    private func shortReason(_ reason: UnplacedReason?) -> String {
        switch reason {
        case .tooLarge: Copy.Results.shortTooLarge
        case .fragileInTheWay: Copy.Results.shortFragile
        case .invalid: Copy.Results.shortInvalid
        case .noRoom, nil: Copy.Results.shortNoRoom
        }
    }

    private func reasonText(_ reason: UnplacedReason?) -> String {
        switch reason {
        case .tooLarge: Copy.Viewer.tooLarge
        case .fragileInTheWay: Copy.Viewer.fragileInTheWay
        case .invalid: Copy.Viewer.invalidSize
        case .noRoom, nil: Copy.Viewer.noRoom
        }
    }

    // MARK: Gestures and camera

    private var orbitGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                if dragStart == nil {
                    dragStart = [controller.azimuth, controller.elevation]
                }
                guard let start = dragStart else { return }
                controller.azimuth = start.x - Float(value.translation.width) * 0.01
                controller.elevation = start.y + Float(value.translation.height) * 0.01
                controller.updateCameraTransform()
            }
            .onEnded { _ in dragStart = nil }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                controller.distance = min(max(0.6, 1.4 / Float(value.magnification)), 3.5)
                controller.updateCameraTransform()
            }
    }

    private var tapGesture: some Gesture {
        SpatialTapGesture()
            .targetedToAnyEntity()
            .onEnded { event in
                var entity: Entity? = event.entity
                while let current = entity {
                    if let id = controller.stepper.itemId(at: current.name),
                       let item = itemsStore.items.first(where: { $0.id == id }) {
                        selectedItem = item
                        return
                    }
                    entity = current.parent
                }
            }
    }

    /// 3D, Top and Side presets for the orbit camera.
    private func applyViewMode() {
        switch viewMode {
        case 1:
            controller.azimuth = 0
            controller.elevation = 85 * .pi / 180
        case 2:
            controller.azimuth = 0
            controller.elevation = 5 * .pi / 180
        default:
            controller.azimuth = .pi / 4
            controller.elevation = .pi / 5
        }
        controller.updateCameraTransform()
    }

    /// Bottom shows the lower third, Middle the lower two thirds, All and Top everything.
    private func applyLayer() {
        let height = controller.stepper.innerDims[safe: 1] ?? 100
        let fractions: [Double] = [.infinity, 1.0 / 3, 2.0 / 3, .infinity]
        let fraction = fractions[layer]
        controller.stepper.peelThreshold = fraction.isFinite ? height * fraction + 0.5 : 10_000
        controller.stepper.applyPeel()
    }

    // MARK: Data

    private var routeLabel: String? {
        guard let trip = tripStore.trip else { return nil }
        var text = "\(trip.from) to \(trip.to)"
        if let start = TripDates.date(trip.departDate) {
            text += " · " + start.formatted(Date.FormatStyle().month(.abbreviated).day())
        }
        return text
    }

    private func itemName(_ id: String) -> String {
        if id == RuleFlag.bagItemId { return Copy.Results.wholeBag }
        return itemsStore.items.first(where: { $0.id == id })?.name ?? id
    }

    private func repack() async {
        guard let trip = tripStore.trip, let bag = tripStore.bag else { return }
        await PackRun.run(
            trip: trip, bag: bag, useChecked: tripStore.useChecked, items: itemsStore.items,
            planStore: planStore, rulesStore: rulesStore, client: client
        )
    }

    private func reloadScene() {
        guard let plan = planStore.plan, let bag = tripStore.bag else { return }
        controller.load(plan: plan, items: itemsStore.items, container: bag, shapes: itemsStore.shapes)
        layer = 0
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
