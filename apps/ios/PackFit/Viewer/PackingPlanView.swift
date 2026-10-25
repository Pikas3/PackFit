import SwiftUI
import Packer

/// Plan tab (Figma "03 · Packing Plan"): the packer's steps as a checklist, by layer.
struct PackingPlanView: View {
    @Environment(PlanStore.self) private var planStore
    @Environment(ItemsStore.self) private var itemsStore
    @Environment(TripStore.self) private var tripStore
    @Environment(AppNavigator.self) private var navigator
    @Binding var path: [Route]

    private typealias P = Tokens.Palette
    private typealias T = Tokens.TypeScale

    /// One checklist row, built from the packer's `describeStep`.
    private struct Step: Identifiable {
        let order: Int
        let title: String
        let detail: String
        let zone: String
        let position: VerticalPosition
        var id: Int { order }
    }

    var body: some View {
        let steps = buildSteps()
        Group {
            if steps.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Tokens.Spacing.lg) {
                        progressCard(steps)
                        ForEach(Array(layers.enumerated()), id: \.offset) { index, layer in
                            let rows = steps.filter { $0.position == layer.position }
                            if !rows.isEmpty {
                                layerSection(number: index + 1, layer: layer, rows: rows)
                            }
                        }
                        proTip
                        Button {
                            withAnimation { planStore.packedSteps = Set(steps.map(\.order)) }
                            path.append(.beforeYouGo)
                        } label: {
                            Label(Copy.PackingPlan.allPacked, systemImage: "checkmark")
                        }
                        .buttonStyle(.snuglyPrimary)
                    }
                    .padding(.horizontal, Tokens.Spacing.screen)
                    .padding(.vertical, Tokens.Spacing.sm)
                }
            }
        }
        .snuglyCanvas()
        .task {
            if planStore.plan == nil, let bag = tripStore.bag, !itemsStore.items.isEmpty {
                await planStore.computePlan(items: itemsStore.items, into: bag)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                NavTitle(title: Copy.PackingPlan.title, subtitle: subtitle)
            }
            if !steps.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: shareText(steps), subject: Text(Copy.PackingPlan.shareTitle))
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: Tokens.Spacing.md) {
            IconBubble(systemImage: "checklist", size: 72, iconSize: 32, radius: Tokens.Radius.card, fill: P.pink100)
            Text(Copy.PackingPlan.empty)
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

    // MARK: Progress

    private func progressCard(_ steps: [Step]) -> some View {
        let done = steps.filter { planStore.packedSteps.contains($0.order) }.count
        let fraction = Double(done) / Double(steps.count)
        let minutes = Int((Double(steps.count - done) * 0.75).rounded(.up))
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Copy.PackingPlan.progress(Int((fraction * 100).rounded())))
                        .font(T.h1)
                        .foregroundStyle(P.textPrimary)
                    Text(Copy.PackingPlan.stepsDone(done, steps.count, minutes: minutes))
                        .font(T.caption)
                        .foregroundStyle(P.pink700)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                IconBubble(systemImage: "suitcase", size: 52, iconSize: 26, radius: 18, fill: P.surface)
            }
            GeometryReader { geo in
                Capsule()
                    .fill(P.surface)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(P.green600)
                            .frame(width: max(geo.size.width * fraction, fraction > 0 ? 10 : 0))
                    }
            }
            .frame(height: 10)
            .accessibilityElement()
            .accessibilityLabel(Copy.PackingPlan.progress(Int((fraction * 100).rounded())))
            .accessibilityValue("\(done) of \(steps.count)")

            FlowLayout {
                ForEach(layers, id: \.title) { layer in
                    let rows = steps.filter { $0.position == layer.position }
                    if !rows.isEmpty {
                        let layerDone = rows.filter { planStore.packedSteps.contains($0.order) }.count
                        Chip(
                            label: Copy.PackingPlan.layerChip(layer.short, layerDone, rows.count),
                            state: layerDone == rows.count ? .complete : .normal
                        )
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(P.pink100, in: RoundedRectangle(cornerRadius: Tokens.Radius.card, style: .continuous))
        .animation(.easeOut(duration: Tokens.Motion.standard), value: done)
    }

    // MARK: Layers

    private struct Layer {
        let position: VerticalPosition
        let title: String
        let short: String
        let caption: String
    }

    private var layers: [Layer] {
        [
            Layer(position: .bottom, title: Copy.PackingPlan.bottomTitle, short: Copy.Results.layerNames[1], caption: Copy.PackingPlan.bottomCaption),
            Layer(position: .middle, title: Copy.PackingPlan.middleTitle, short: Copy.Results.layerNames[2], caption: Copy.PackingPlan.middleCaption),
            Layer(position: .top, title: Copy.PackingPlan.topTitle, short: Copy.Results.layerNames[3], caption: Copy.PackingPlan.topCaption),
        ]
    }

    private func layerSection(number: Int, layer: Layer, rows: [Step]) -> some View {
        let allDone = rows.allSatisfy { planStore.packedSteps.contains($0.order) }
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(number: "\(number)", title: layer.title, caption: layer.caption, tone: allDone ? .green : .pink)
            VStack(spacing: Tokens.Spacing.sm) {
                ForEach(rows) { step in
                    let done = planStore.packedSteps.contains(step.order)
                    Button {
                        withAnimation(.easeOut(duration: Tokens.Motion.quick)) {
                            if done {
                                planStore.packedSteps.remove(step.order)
                            } else {
                                planStore.packedSteps.insert(step.order)
                            }
                        }
                    } label: {
                        ChecklistRow(
                            step: Copy.PackingPlan.step(step.order + 1),
                            title: step.title,
                            detail: step.detail,
                            zone: step.zone,
                            done: done
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var proTip: some View {
        HStack(alignment: .top, spacing: 10) {
            IconBubble(systemImage: "lightbulb", size: 32, iconSize: 16, radius: 10, fill: P.surface)
            VStack(alignment: .leading, spacing: 2) {
                Text(Copy.PackingPlan.proTip).eyebrow(P.pink700)
                Text(Copy.PackingPlan.proTipBody)
                    .font(T.caption)
                    .foregroundStyle(P.textPrimary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(P.pink100, in: RoundedRectangle(cornerRadius: Tokens.Radius.lg, style: .continuous))
    }

    // MARK: Data

    private var subtitle: String? {
        guard let trip = tripStore.trip else { return nil }
        let place = AirportCatalog.name(for: trip.to) ?? trip.to
        return "\(place) · \(tripStore.bag?.name ?? (tripStore.useChecked ? Copy.Trip.checkedBag : Copy.Trip.carryOnBag))"
    }

    private func buildSteps() -> [Step] {
        guard let plan = planStore.plan else { return [] }
        let items = itemsStore.items
        return plan.placed.map(\.order).sorted().compactMap { order in
            guard let step = describeStep(plan, items: items, order: order, container: tripStore.bag) else { return nil }
            let detail: String
            if let note = step.notes.first {
                detail = note.capitalizedFirst
            } else if !step.near.isEmpty {
                detail = Copy.PackingPlan.nextTo(step.near)
            } else {
                detail = step.region.capitalizedFirst
            }
            return Step(
                order: order,
                title: step.item.name,
                detail: detail,
                zone: zoneTag(step.region),
                position: step.position
            )
        }
    }

    /// "back left corner" becomes "Back left"; "across the whole bag" becomes "Whole bag".
    private func zoneTag(_ region: String) -> String {
        if region == "across the whole bag" { return "Whole bag" }
        return region.replacingOccurrences(of: " corner", with: "").capitalizedFirst
    }

    private func shareText(_ steps: [Step]) -> String {
        var lines = [Copy.PackingPlan.shareTitle]
        for layer in layers {
            let rows = steps.filter { $0.position == layer.position }
            guard !rows.isEmpty else { continue }
            lines.append("")
            lines.append(layer.title)
            for step in rows {
                lines.append("\(step.order + 1). \(step.title) (\(step.zone.lowercased())): \(step.detail)")
            }
        }
        return lines.joined(separator: "\n")
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
