import Foundation
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
    private(set) var placements: [Placement] = []
    private(set) var innerDims: [Double] = []
    private var itemsById: [String: Item] = [:]
    private var playTask: Task<Void, Never>?

    /// Origin at the compartment's inner bottom-left-back corner, metres.
    let root = Entity()

    init(pastOpacity: CGFloat = 0.85) {
        self.pastOpacity = pastOpacity
    }

    /// Loads the first compartment's placements. Other compartments are not drawn.
    func load(plan: Plan, items: [Item], container: Container, style: ContainerStyle) {
        stopPlay()
        root.children.forEach { $0.removeFromParent() }
        itemEntities.removeAll()
        let main = container.compartments.first
        innerDims = main?.dims ?? container.outer
        placements = plan.placed
            .filter { $0.compartment == nil || $0.compartment == main?.name }
            .sorted { $0.order < $1.order }
        itemsById = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

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
            let entity = SceneBuilder.buildItemEntity(placement: placement, item: item)
            root.addChild(entity)
            itemEntities[placement.itemId] = entity
        }
        goToStep(style == .wireframe ? 0 : placements.count, animated: false)
    }

    var stepCount: Int { placements.count }

    /// The item placed by the current step, if any.
    var currentPlacement: Placement? {
        let i = currentStep - 1
        return placements.indices.contains(i) ? placements[i] : nil
    }

    var currentItem: Item? { currentPlacement.flatMap { itemsById[$0.itemId] } }

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
            guard let entity = itemEntities[placement.itemId] else { continue }
            let base = SIMD3<Float>(
                Float(placement.w) * SceneBuilder.cmToMeters,
                Float(placement.h) * SceneBuilder.cmToMeters,
                Float(placement.d) * SceneBuilder.cmToMeters
            )
            let peeled = placement.y + placement.h > peelThreshold
            guard index < currentStep, !peeled else {
                entity.isEnabled = false
                continue
            }
            entity.isEnabled = true
            let isCurrent = index == currentStep - 1
            entity.scale = isCurrent ? base * 1.03 : base
            if let item = itemsById[placement.itemId] {
                entity.model?.materials = [CategoryMaterials.material(for: item.category, opacity: isCurrent ? 1 : pastOpacity)]
            }
        }
    }
}
