import SwiftUI
import RealityKit

#if canImport(ARKit) && !targetEnvironment(simulator)
@preconcurrency import ARKit

struct ARScanRepresentable: UIViewRepresentable {
    let controller: LidarSessionController

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero)
        view.session = controller.session
        view.environment.background = .cameraFeed()
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        view.addGestureRecognizer(tap)
        context.coordinator.view = view
        return view
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        context.coordinator.controller = controller
        if let box = controller.previewBox {
            context.coordinator.showPreview(box: box)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(controller: controller)
    }

    @MainActor
    final class Coordinator: NSObject {
        var controller: LidarSessionController
        weak var view: ARView?
        private var boxEntity: ModelEntity?

        init(controller: LidarSessionController) {
            self.controller = controller
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let view else { return }
            let point = gesture.location(in: view)
            controller.handleTap(screenPoint: point, viewSize: view.bounds.size)
        }

        func showPreview(box: MeasuredBox) {
            guard let view else { return }
            boxEntity?.removeFromParent()
            let meters = SIMD3<Float>(Float(box.w) / 100, Float(box.h) / 100, Float(box.d) / 100)
            var material = SimpleMaterial(color: .cyan.withAlphaComponent(0.35), isMetallic: false)
            material.triangleFillMode = .fill
            let entity = ModelEntity(
                mesh: .generateBox(size: meters),
                materials: [material]
            )
            entity.position = SIMD3(0, meters.y / 2, -0.5)
            let anchor = AnchorEntity(world: .zero)
            anchor.addChild(entity)
            view.scene.anchors.removeAll()
            view.scene.addAnchor(anchor)
            boxEntity = entity
        }
    }
}
#else
struct ARScanRepresentable: View {
    let controller: LidarSessionController
    var body: some View {
        Color.black.opacity(0.85)
            .overlay {
                Text(controller.statusText)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding()
            }
    }
}
#endif
