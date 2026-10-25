import Foundation
import Packer
import RealityKit
import SwiftUI

/// Plan entities plus step, play and peel state. Shared by the 3D viewer and the AR overlay,
/// and the object Section 4's voice coach drives through `PlanViewerControlling`.
@MainActor
@Observable
final class PlanStepper: PlanViewerControlling {
    enum ContainerStyle {
        /// Translucent volume, edges and lid plane (non-AR viewer).
        case volume
        /// Edges only, so the real bag shows through (AR overlay).
        case wireframe
    }

    private(set) var currentStep: Int = 0
    var onStepChange: ((Int) -> Void)?

    var peelThreshold: Double = 10_000
    private(set) var isPlaying = false
    let pastOpacity: CGFloat

    private(set) var itemEntities: [String: ModelEntity] = [:]
    /// Each entity's resting scale. Cylinders lying down are rotated, so it is not simply w, h, d.
    private var baseScales: [String: SIMD3<Float>] = [:]
    /// Name tag over the current item, rebuilt on each step.
    private let label = Entity()
    private(set) var placements: [Placement] = []
    private(set) var innerDims: [Double] = []
    private var itemsById: [String: Item] = [:]
    private var plan: Plan?
    private var container: Container?
    private var playTask: Task<Void, Never>?

    /// Origin at the compartment's inner bottom-left-back corner, metres.
    let root = Entity()

    init(pastOpacity: CGFloat = 0.85) {
        self.pastOpacity = pastOpacity
    }

    /// Loads the first compartment's placements. Other compartments are not drawn.
    func load(
        plan: Plan, items: [Item], container: Container, style: ContainerStyle,
        shapes: [String: ObjectShape] = [:]
    ) {
        stopPlay()
        root.children.forEach { $0.removeFromParent() }
        itemEntities.removeAll()
        baseScales.removeAll()
        let main = container.compartments.first
        innerDims = main?.dims ?? container.outer
        placements = plan.placed
            .filter { $0.compartment == nil || $0.compartment == main?.name }
            .sorted { $0.order < $1.order }
        itemsById = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        self.plan = plan
        self.container = container

        switch style {
        case .volume:
            root.addChild(SceneBuilder.buildContainer(outer: innerDims, type: container.type))
        case .wireframe:
            let size = SIMD3<Float>(innerDims.map { Float($0) * SceneBuilder.cmToMeters })
            let frame = Entity()
            frame.name = "container"
            for edge in SceneBuilder.edgeEntities(size: size, color: UIColor.white.withAlphaComponent(0.9), thickness: 0.004) {
                frame.addChild(edge)
            }
            root.addChild(frame)
        }

        for placement in placements {
            guard let item = itemsById[placement.itemId] else { continue }
            let entity = SceneBuilder.buildItemEntity(placement: placement, item: item, shape: shapes[placement.itemId])
            root.addChild(entity)
            itemEntities[placement.itemId] = entity
            baseScales[placement.itemId] = entity.scale
        }
        root.addChild(label)
        goToStep(style == .wireframe ? 0 : placements.count, animated: false)
    }

    var stepCount: Int { placements.count }

    /// The item placed by the current step, if any.
    var currentPlacement: Placement? {
        let i = currentStep - 1
        return placements.indices.contains(i) ? placements[i] : nil
    }

    var currentItem: Item? { currentPlacement.flatMap { itemsById[$0.itemId] } }

    /// Packer notes for the current step, e.g. "keep upright" or "lay it flat".
    var currentNotes: [String] {
        guard let plan, let order = currentPlacement?.order else { return [] }
        return describeStep(plan, items: Array(itemsById.values), order: order, container: container)?.notes ?? []
    }

    func goToStep(_ n: Int, animated: Bool) {
        let clamped = max(0, min(n, placements.count))
        currentStep = clamped
        applyStepAppearance(animated: animated)
        onStepChange?(clamped)
    }

    func togglePlay(reduceMotion: Bool) {
        if isPlaying {
            stopPlay()
            return
        }
        isPlaying = true
        playTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let next = self.currentStep >= self.placements.count ? 0 : self.currentStep + 1
                self.goToStep(next, animated: !reduceMotion)
                if next >= self.placements.count {
                    self.stopPlay()
                    break
                }
                let ns = reduceMotion ? 0 : UInt64(Tokens.Motion.stepSeconds * 1_000_000_000)
                try? await Task.sleep(nanoseconds: ns)
            }
        }
    }

    func stopPlay() {
        isPlaying = false
        playTask?.cancel()
        playTask = nil
    }

    func applyPeel() {
        applyStepAppearance(animated: false)
    }

    func itemId(at entityName: String?) -> String? {
        guard let entityName, itemEntities[entityName] != nil else { return nil }
        return entityName
    }

    private func applyStepAppearance(animated: Bool) {
        _ = animated
        for (index, placement) in placements.enumerated() {
            guard let entity = itemEntities[placement.itemId],
                  let base = baseScales[placement.itemId] else { continue }
            let peeled = placement.y + placement.h > peelThreshold
            guard index < currentStep, !peeled else {
                entity.isEnabled = false
                continue
            }
            entity.isEnabled = true
            let isCurrent = index == currentStep - 1
            entity.scale = isCurrent ? base * 1.03 : base
            // Models are several parts, so opacity goes on the parent and reaches them all.
            if isCurrent || pastOpacity >= 1 {
                entity.components.remove(OpacityComponent.self)
            } else {
                entity.components.set(OpacityComponent(opacity: Float(pastOpacity)))
            }
        }
        updateLabel()
    }

    private func updateLabel() {
        label.children.forEach { $0.removeFromParent() }
        guard let placement = currentPlacement, let item = currentItem,
              placement.y + placement.h <= peelThreshold else { return }
        let tag = SceneBuilder.buildLabel(item.name)
        label.addChild(tag)
        // Above the bag's rim as well as the item, so other items and the lid never hide it.
        let top = max(placement.y + placement.h, innerDims.count == 3 ? innerDims[1] : 0)
        label.position = [
            Float(placement.x + placement.w / 2) * SceneBuilder.cmToMeters,
            Float(top) * SceneBuilder.cmToMeters + 0.04,
            Float(placement.z + placement.d / 2) * SceneBuilder.cmToMeters,
        ]
    }
}
