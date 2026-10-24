import AVFoundation
import SwiftUI
import UIKit
import simd

/// Camera preview + projected wireframes for the guided LiDAR flow (no ARKit).
struct GuidedCameraView: UIViewRepresentable {
    let session: GuidedSession

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> PreviewHostView {
        let host = PreviewHostView()
        host.preview.session = session.capture.session
        host.preview.videoGravity = .resizeAspectFill
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        host.addGestureRecognizer(tap)
        context.coordinator.host = host
        context.coordinator.parent = self
        return host
    }

    func updateUIView(_ host: PreviewHostView, context: Context) {
        context.coordinator.parent = self
        host.preview.session = session.capture.session
        host.overlay.wires = session.liveWires
        host.overlay.snapshot = session.latestSnapshot
        host.overlay.setNeedsDisplay()
    }

    @MainActor
    final class Coordinator: NSObject {
        weak var host: PreviewHostView?
        var parent: GuidedCameraView?

        @objc func tapped(_ gesture: UITapGestureRecognizer) {
            guard let host, let parent else { return }
            parent.session.handleTap(at: gesture.location(in: host), in: host.bounds.size)
        }
    }
}

final class PreviewHostView: UIView {
    let preview = AVCaptureVideoPreviewLayer()
    let overlay = WireOverlayView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        layer.addSublayer(preview)
        overlay.backgroundColor = .clear
        overlay.isUserInteractionEnabled = false
        addSubview(overlay)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        preview.frame = bounds
        overlay.frame = bounds
    }
}

/// Draws `LiveWire` boxes by projecting world corners with the latest depth snapshot.
final class WireOverlayView: UIView {
    var wires: [LiveWire] = []
    var snapshot: DepthSnapshot?

    private static let edges: [(Int, Int)] = [
        (0, 1), (1, 2), (2, 3), (3, 0),
        (4, 5), (5, 6), (6, 7), (7, 4),
        (0, 4), (1, 5), (2, 6), (3, 7),
    ]

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext(), let snapshot else { return }
        let size = bounds.size
        for wire in wires {
            let pts: [CGPoint?] = wire.corners.map { world in
                guard let n = snapshot.project(world) else { return nil }
                // Landscape sensor UV → portrait preview (inverse of sensorUV).
                let portrait = SIMD2(1 - n.y, n.x)
                return CGPoint(x: CGFloat(portrait.x) * size.width, y: CGFloat(portrait.y) * size.height)
            }
            ctx.setStrokeColor(red: CGFloat(wire.color.x), green: CGFloat(wire.color.y), blue: CGFloat(wire.color.z), alpha: CGFloat(wire.color.w))
            ctx.setLineWidth(2.5)
            for (a, b) in Self.edges {
                guard let pa = pts[a], let pb = pts[b] else { continue }
                ctx.move(to: pa)
                ctx.addLine(to: pb)
            }
            ctx.strokePath()

            if let label = wire.label, let top = pts[4...7].compactMap({ $0 }).first {
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.boldSystemFont(ofSize: 16),
                    .foregroundColor: UIColor.white,
                ]
                (label as NSString).draw(at: CGPoint(x: top.x - 6, y: top.y - 22), withAttributes: attrs)
            }
        }
    }
}
