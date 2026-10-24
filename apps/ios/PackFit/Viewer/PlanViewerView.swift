import SwiftUI
import RealityKit

struct PlanViewerView: View {
    @Environment(PlanStore.self) private var planStore
    @Environment(ItemsStore.self) private var itemsStore
    @Environment(TripStore.self) private var tripStore
    @Environment(RulesStore.self) private var rulesStore

    @State private var controller = PlanViewerController()
    @State private var selectedItem: Item?
    @State private var dragStart: SIMD2<Float>?

    var body: some View {
        VStack(spacing: 0) {
            reality
                .gesture(orbitGesture)
                .gesture(magnifyGesture)
                .simultaneousGesture(tapGesture)

            controls
        }
        .background(Tokens.Color.surface)
        .navigationTitle(Copy.Viewer.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(Copy.Viewer.openRules, value: Route.rules)
            }
        }
        .sheet(item: $selectedItem) { item in
            ItemDetailView(item: item, flags: rulesStore.flags(for: item.id))
        }
        .task {
            if planStore.plan == nil, let bag = tripStore.bag {
                await planStore.computePlan(items: itemsStore.items, into: bag)
            }
            reloadScene()
        }
        .onChange(of: planStore.plan) { _, _ in reloadScene() }
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
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
            if let stats = planStore.plan?.stats {
                HStack {
                    Label(String(format: "%@ %.0f%%", Copy.Viewer.fill, stats.fillPct), systemImage: "cube")
                    Spacer()
                    Label(String(format: "%@ %.1f kg", Copy.Viewer.weight, stats.kg), systemImage: "scalemass")
                }
                .font(Tokens.TypeScale.caption)
            }

            PlanStepControls(stepper: controller.stepper)

            Text(Copy.Viewer.peel)
                .font(Tokens.TypeScale.caption)
            Slider(
                value: Binding(
                    get: { controller.stepper.peelThreshold },
                    set: {
                        controller.stepper.peelThreshold = $0
                        controller.stepper.applyPeel()
                    }
                ),
                in: 0...80
            )

            if let unplaced = planStore.plan?.unplaced, !unplaced.isEmpty {
                Text("\(Copy.Viewer.unplaced): \(unplaced.count)")
                    .font(Tokens.TypeScale.caption)
                    .foregroundStyle(Tokens.Color.restricted)
            }
        }
        .packFitScreenPadding()
        .background(.ultraThinMaterial)
    }

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

    private func reloadScene() {
        guard let plan = planStore.plan, let bag = tripStore.bag else { return }
        controller.load(plan: plan, items: itemsStore.items, container: bag)
    }
}
