import Foundation
import RealityKit
import SwiftUI

/// The non-AR viewer: a `PlanStepper` plus an orbit camera.
@MainActor
@Observable
final class PlanViewerController: PlanViewerControlling {
    // Solid past items: models are several parts, and see-through parts muddy each other.
    let stepper = PlanStepper(pastOpacity: 1)

    var currentStep: Int { stepper.currentStep }
    var onStepChange: ((Int) -> Void)? {
        get { stepper.onStepChange }
        set { stepper.onStepChange = newValue }
    }

    var root: Entity { stepper.root }
    let cameraPivot = Entity()
    let camera = PerspectiveCamera()

    var azimuth: Float = .pi / 4
    var elevation: Float = .pi / 5
    var distance: Float = 1.4

    func load(plan: Plan, items: [Item], container: Container, shapes: [String: ObjectShape] = [:]) {
        stepper.load(plan: plan, items: items, container: container, style: .volume, shapes: shapes)
        let dims = stepper.innerDims
        cameraPivot.position = SIMD3<Float>(dims.map { Float($0) * SceneBuilder.cmToMeters / 2 })
        camera.name = "orbit-camera"
        if camera.parent == nil {
            cameraPivot.addChild(camera)
        }
        updateCameraTransform()
    }

    func goToStep(_ n: Int, animated: Bool) {
        stepper.goToStep(n, animated: animated)
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
}
