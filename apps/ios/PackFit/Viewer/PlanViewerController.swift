import Foundation
import RealityKit
import SwiftUI

@MainActor
@Observable
final class PlanViewerController: PlanViewerControlling {
    private(set) var currentStep: Int = 0
    var onStepChange: ((Int) -> Void)?

    var peelThreshold: Double = 10_000
    var isPlaying = false

    private(set) var itemEntities: [String: ModelEntity] = [:]
    private(set) var placements: [Placement] = []
    private var itemsById: [String: Item] = [:]
    private var playTask: Task<Void, Never>?

    let root = Entity()
    let cameraPivot = Entity()
    let camera = PerspectiveCamera()

    var azimuth: Float = .pi / 4
    var elevation: Float = .pi / 5
    var distance: Float = 1.4

    func load(plan: Plan, items: [Item], container: Container) {
        root.children.forEach { $0.removeFromParent() }
        itemEntities.removeAll()
        placements = plan.placed.sorted { $0.order < $1.order }
        itemsById = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })

        let bag = SceneBuilder.buildContainer(outer: container.compartments.first?.dims ?? container.outer, type: container.type)
        root.addChild(bag)

        for placement in placements {
            guard let item = itemsById[placement.itemId] else { continue }
            let entity = SceneBuilder.buildItemEntity(placement: placement, item: item)
            root.addChild(entity)
            itemEntities[placement.itemId] = entity
        }

        cameraPivot.position = [
            Float((container.outer[0]) * 0.01) / 2,
            Float((container.outer[1]) * 0.01) / 2,
            Float((container.outer[2]) * 0.01) / 2
        ]
        camera.name = "orbit-camera"
        if camera.parent == nil {
            cameraPivot.addChild(camera)
        }
        updateCameraTransform()
        goToStep(placements.count, animated: false)
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

    func updateCameraTransform() {
        let elev = min(max(elevation, 5 * .pi / 180), 85 * .pi / 180)
        elevation = elev
        let x = distance * cos(elev) * sin(azimuth)
        let y = distance * sin(elev)
        let z = distance * cos(elev) * cos(azimuth)
        camera.position = [x, y, z]
        camera.look(at: .zero, from: camera.position, relativeTo: cameraPivot)
    }

    func applyPeel() {
        for placement in placements {
            guard let entity = itemEntities[placement.itemId] else { continue }
            let top = placement.y + placement.h
            if top > peelThreshold {
                entity.isEnabled = false
            }
        }
        applyStepAppearance(animated: false)
    }

    private func applyStepAppearance(animated: Bool) {
        _ = animated
        for placement in placements {
            guard let entity = itemEntities[placement.itemId] else { continue }
            let item = itemsById[placement.itemId]
            let top = placement.y + placement.h
            if top > peelThreshold {
                entity.isEnabled = false
                continue
            }
            if placement.order >= currentStep {
                entity.isEnabled = false
            } else if placement.order == currentStep - 1 {
                entity.isEnabled = true
                entity.scale = entity.scale // keep dims
                // Brighten current: slight scale pulse via 1.03 on base size.
                let base = SIMD3<Float>(
                    Float(placement.w) * SceneBuilder.cmToMeters,
                    Float(placement.h) * SceneBuilder.cmToMeters,
                    Float(placement.d) * SceneBuilder.cmToMeters
                )
                entity.scale = base * 1.03
                if let item {
                    entity.model?.materials = [CategoryMaterials.material(for: item.category, opacity: 1)]
                }
            } else {
                entity.isEnabled = true
                let base = SIMD3<Float>(
                    Float(placement.w) * SceneBuilder.cmToMeters,
                    Float(placement.h) * SceneBuilder.cmToMeters,
                    Float(placement.d) * SceneBuilder.cmToMeters
                )
                entity.scale = base
                if let item {
                    entity.model?.materials = [CategoryMaterials.material(for: item.category, opacity: 0.85)]
                }
            }
        }
    }

    func itemId(at entityName: String?) -> String? {
        guard let entityName, itemEntities[entityName] != nil else { return nil }
        return entityName
    }
}
