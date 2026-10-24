import ARKit
import RealityKit
import SwiftUI

/// The camera view for the guided flow. Uses the session's own `ARSession` and never lets
/// `ARView` configure one itself.
struct GuidedARView: UIViewRepresentable {
    let session: GuidedSession
    /// The trip's bag, used for the corner-tap fallback's missing sizes.
    let presetBag: Container?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        view.session = session.session
        view.renderOptions.insert(.disableMotionBlur)
        view.scene.addAnchor(session.worldRoot)
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        view.addGestureRecognizer(tap)
        context.coordinator.view = view
        context.coordinator.parent = self
        return view
    }

    func updateUIView(_ view: ARView, context: Context) {
        context.coordinator.parent = self
        if let anchor = session.overlayEntity, anchor.scene == nil {
            view.scene.addAnchor(anchor)
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        weak var view: ARView?
        var parent: GuidedARView?

        @objc func tapped(_ gesture: UITapGestureRecognizer) {
            guard let view, let parent else { return }
            let point = gesture.location(in: view)
            let session = parent.session
            if session.isCornerMode {
                if let hit = view.raycast(from: point, allowing: .estimatedPlane, alignment: .horizontal).first {
                    let c = hit.worldTransform.columns.3
                    session.handleCornerTap([c.x, c.y, c.z], preset: parent.presetBag)
                }
                return
            }
            if session.phase == .items, let entity = view.entity(at: point) {
                session.dropItem(entityName: entity.name)
            }
        }
    }
}
