import SwiftUI

/// Full-screen guided flow: bag, items, review, then the plan inside the real bag.
struct GuidedScanView: View {
    @Environment(TripStore.self) private var tripStore
    @Environment(ItemsStore.self) private var itemsStore
    @Environment(PlanStore.self) private var planStore
    @Environment(DeviceCapabilities.self) private var caps
    @Binding var path: [Route]

    @State private var session: GuidedSession
    @State private var editing: Item?

    init(path: Binding<[Route]>, client: any APIClient) {
        _path = path
        _session = State(initialValue: GuidedSession(client: client))
    }

    var body: some View {
        Group {
            if caps.supportsAR {
                ZStack {
                    GuidedARView(session: session)
                        .ignoresSafeArea()
                    if showsReticle {
                        Circle()
                            .stroke(.white, lineWidth: 2)
                            .frame(width: 18, height: 18)
                            .shadow(radius: 2)
                            .allowsHitTesting(false)
                    }
                    VStack(spacing: 0) {
                        banner
                        Spacer()
                        panel
                    }
                }
            } else {
                EmptyStateView(Copy.Guided.noAR, actionTitle: Copy.Guided.usePresets) {
                    path.append(.bagSetup)
                }
            }
        }
        .navigationTitle(Copy.Guided.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(Copy.Guided.usePresets) { path.append(.bagSetup) }
                    Button(Copy.Guided.addManually) { path.append(.scan) }
                    Button(Copy.Guided.restart, role: .destructive) { session.restart() }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .onAppear {
            session.presetBag = tripStore.bag
            if caps.supportsAR { session.start() }
        }
        .onDisappear { session.stop() }
        .sheet(isPresented: reviewBinding) { reviewSheet }
    }

    /// The LiDAR bag scan aims with the reticle; taps aim with the finger, so the reticle
    /// marks the screen centre as a hint only when nothing else is drawn.
    private var showsReticle: Bool {
        session.phase == .bag && !session.isCornerMode
    }

    // MARK: Banner

    private var banner: some View {
        Text(bannerText)
            .font(Tokens.TypeScale.callout)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(Tokens.Spacing.md)
            .background(.ultraThinMaterial)
    }

    private var bannerText: String {
        if let error = session.errorText { return error }
        switch session.phase {
        case .findFloor: return Copy.Guided.findFloor
        case .bag:
            if session.isCornerMode {
                switch session.cornerTaps.count {
                case 0: return Copy.Guided.tapCornerLeft
                case 1: return Copy.Guided.tapCornerRight
                default: return Copy.Guided.tapCornerFront
                }
            }
            return session.canLockBag ? Copy.Guided.bagStable : Copy.Guided.bag
        case .items:
            guard session.isTapMeasuring else { return Copy.Guided.items }
            switch session.tapStep {
            case .corner(1): return Copy.Guided.tapItemCorner1
            case .corner(2): return Copy.Guided.tapItemCorner2
            case .corner: return Copy.Guided.tapItemCorner3
            case .top: return Copy.Guided.tapItemTop
            case .adjust: return Copy.Guided.tapItemAdjust
            }
        case .identifying: return Copy.Guided.identifying
        case .review: return Copy.Guided.review
        case .packing: return Copy.Guided.packing
        case .overlay:
            if let placement = session.stepper.currentPlacement, let depth = session.shellDepthCm,
               placement.y + placement.h > depth + 0.5 {
                return Copy.Guided.underLid
            }
            return Copy.Guided.overlay
        }
    }

    // MARK: Bottom panel

    @ViewBuilder
    private var panel: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
            switch session.phase {
            case .findFloor:
                ProgressView()
                    .frame(maxWidth: .infinity)
            case .bag:
                bagPanel
            case .items:
                itemsPanel
            case .identifying:
                HStack {
                    ProgressView()
                    Text("\(session.identifyProgress)/\(session.tracked.filter(\.stable).count)")
                        .font(Tokens.TypeScale.callout)
                }
                .frame(maxWidth: .infinity)
            case .review:
                Text(Copy.Guided.review)
                    .font(Tokens.TypeScale.callout)
            case .packing:
                ProgressView()
                    .frame(maxWidth: .infinity)
            case .overlay:
                overlayPanel
            }
        }
        .packFitScreenPadding()
        .background(.ultraThinMaterial)
    }

    private var bagPanel: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
            if let cavity = session.liveCavity, !session.isCornerMode {
                let box = cavity.fit.box
                Text(String(format: "%.0f × %.0f cm, %.0f cm deep", box.rect.long * 100, box.rect.short * 100, box.height * 100))
                    .font(Tokens.TypeScale.title)
                ConfidenceBadge(confidence: cavity.confidence)
            }
            HStack {
                if session.isCornerMode {
                    Button(session.hasDepth ? "Cancel" : Copy.Guided.redo) { session.cancelCornerTaps() }
                        .disabled(!session.hasDepth && session.cornerTaps.isEmpty)
                } else if session.showCornerFallback {
                    Button(Copy.Guided.tapCorners) { session.beginCornerTaps() }
                        .font(Tokens.TypeScale.caption)
                }
                Spacer()
                if !session.isCornerMode {
                    Button(Copy.Guided.useBag) { session.lockBag() }
                        .buttonStyle(.borderedProminent)
                        .tint(Tokens.Color.brand)
                        .disabled(!session.canLockBag)
                }
            }
        }
    }

    private var itemsPanel: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
            if session.isTapMeasuring {
                tapPanel
            } else if session.hasDepth {
                Button(Copy.Guided.measureByTapping) { session.startTapMeasuring() }
                    .font(Tokens.TypeScale.caption)
            }
            let found = session.tracked.filter(\.stable)
            Text("\(found.count) \(Copy.Guided.itemsFound)")
                .font(Tokens.TypeScale.title)
            if !session.tracked.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Tokens.Spacing.sm) {
                        ForEach(session.tracked) { t in
                            let cm = t.fit.dimsCm
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(t.number)").font(Tokens.TypeScale.callout.bold())
                                Text(String(format: "%.0f×%.0f×%.0f", cm.w, cm.d, cm.h))
                                    .font(Tokens.TypeScale.caption)
                            }
                            .padding(Tokens.Spacing.sm)
                            .background(
                                (t.stable ? Color.green : Color.orange).opacity(0.2),
                                in: RoundedRectangle(cornerRadius: Tokens.Radius.sm)
                            )
                        }
                    }
                }
                if !session.isTapMeasuring {
                    Text(Copy.Guided.itemsHint)
                        .font(Tokens.TypeScale.caption)
                        .foregroundStyle(.secondary)
                }
            }
            HStack {
                Spacer()
                Button(Copy.Guided.done) { Task { await session.identifyItems() } }
                    .buttonStyle(.borderedProminent)
                    .tint(Tokens.Color.brand)
                    .disabled(!session.canFinishItems)
            }
        }
    }

    /// Size fields after the four taps, so every measured value can be corrected (rule 6).
    @ViewBuilder
    private var tapPanel: some View {
        if session.draft?.hasHeight == true {
            VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
                dimStepper(Copy.Guided.lengthCm, \.longCm)
                dimStepper(Copy.Guided.widthCm, \.shortCm)
                dimStepper(Copy.Guided.heightCm, \.heightCm)
                ConfidenceBadge(confidence: TapMeasure.confidence(heightFromSurface: session.draft?.heightFromSurface ?? false))
            }
        }
        HStack {
            if session.hasDepth {
                Button(Copy.Guided.backToSweep) { session.stopTapMeasuring() }
            }
            Spacer()
            Button(Copy.Guided.redo) { session.resetDraft() }
                .disabled(session.itemTaps.isEmpty)
            Button(Copy.Guided.addItem) { session.addDraftItem() }
                .buttonStyle(.bordered)
                .disabled(session.draft?.hasHeight != true)
        }
        .font(Tokens.TypeScale.callout)
    }

    private func dimStepper(_ label: String, _ key: WritableKeyPath<GuidedSession.TapDraft, Double>) -> some View {
        Stepper(
            value: Binding(
                get: { session.draft?[keyPath: key] ?? 0 },
                set: { value in
                    session.draft?[keyPath: key] = max(0.5, value)
                    session.refreshDraftWire()
                }
            ),
            in: 0.5...200,
            step: 0.5
        ) {
            Text(String(format: "%@ %.1f cm", label, session.draft?[keyPath: key] ?? 0))
                .font(Tokens.TypeScale.callout)
        }
    }

    private var overlayPanel: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
            PlanStepControls(stepper: session.stepper)
            if let unplaced = planStore.plan?.unplaced, !unplaced.isEmpty {
                Text("\(Copy.Viewer.unplaced): \(unplaced.count)")
                    .font(Tokens.TypeScale.caption)
                    .foregroundStyle(Tokens.Color.restricted)
            }
            HStack {
                Button(Copy.Guided.view3D) { path.append(.planViewer) }
                Spacer()
                Button(Copy.Guided.itemsLink) { path.append(.itemList) }
                Spacer()
                Button(Copy.Viewer.openRules) { path.append(.rules) }
            }
            .font(Tokens.TypeScale.callout)
        }
    }

    // MARK: Review

    private var reviewBinding: Binding<Bool> {
        Binding(
            get: { session.phase == .review },
            set: { shown in
                if !shown && session.phase == .review { session.backToItems() }
            }
        )
    }

    private var reviewSheet: some View {
        NavigationStack {
            List {
                ForEach(session.items) { item in
                    Button { editing = item } label: {
                        VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
                            Text(item.name)
                                .font(Tokens.TypeScale.body)
                                .foregroundStyle(.primary)
                            Text(String(format: "%.1f×%.1f×%.1f cm · %.2f kg", item.w, item.h, item.d, item.kg))
                                .font(Tokens.TypeScale.caption)
                                .foregroundStyle(.secondary)
                            HStack {
                                MeasurementMethodBadge(method: item.measurement?.method, tapMeasured: item.measurement?.method == .manual)
                                ConfidenceBadge(confidence: item.measurement?.confidence ?? item.confidence)
                            }
                        }
                    }
                }
                .onDelete { session.items.remove(atOffsets: $0) }
            }
            .navigationTitle(Copy.Guided.review)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Copy.Guided.rescan) { session.backToItems() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(Copy.Guided.packIt) {
                        Task { await session.pack(itemsStore: itemsStore, tripStore: tripStore, planStore: planStore) }
                    }
                    .disabled(session.items.isEmpty)
                }
            }
            .sheet(item: $editing) { item in
                ItemDetailView(item: item, flags: []) { updated in
                    if let i = session.items.firstIndex(where: { $0.id == updated.id }) {
                        session.items[i] = updated
                    }
                    editing = nil
                }
            }
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(session.phase == .packing)
    }
}
