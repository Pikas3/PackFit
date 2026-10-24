import ARKit
import RealityKit
import SwiftUI

/// The camera view for the guided flow. Uses the session's own `ARSession` and never lets
/// `ARView` configure one itself.
struct GuidedARView: UIViewRepresentable {
    let session: GuidedSession

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        view.session = session.session
        // Built-in coaching tells the user to move the phone until ARKit finds the floor.
        let coaching = ARCoachingOverlayView()
        coaching.session = session.session
        coaching.goal = .horizontalPlane
        coaching.activatesAutomatically = true
        coaching.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(coaching)
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
            parent.session.handleTap(at: gesture.location(in: view), in: view)
        }
    }
}
