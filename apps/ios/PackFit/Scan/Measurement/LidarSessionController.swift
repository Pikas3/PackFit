import Foundation
import RealityKit
import simd
import CoreImage
import CoreVideo
#if canImport(ARKit)
@preconcurrency import ARKit
#endif

struct MeasuredBox: Equatable, Sendable {
    var w: Double
    var h: Double
    var d: Double
    var confidence: Double
    var method: MeasureMethod
}

@MainActor
@Observable
final class LidarSessionController: NSObject {
    enum Phase: Equatable {
        case waitingForPlane
        case tapFirstCorner
        case tapSecondCorner
        case refiningHeight
        case preview(MeasuredBox)
        case unavailable
    }

    var phase: Phase = .waitingForPlane
    var statusText: String = Copy.Scan.findPlane
    var lastCapturedBase64: String?
    var previewBox: MeasuredBox?

    #if canImport(ARKit)
    nonisolated(unsafe) let session = ARSession()
    private var planeAnchor: ARPlaneAnchor?
    private var cornerA: SIMD3<Float>?
    private var footprint: MeasurementMath.Footprint?
    #endif

    private let hasLidar: Bool

    init(hasLidar: Bool) {
        self.hasLidar = hasLidar
        super.init()
        if !hasLidar {
            phase = .unavailable
            statusText = Copy.Scan.referenceCardHint
        }
    }

    func start() {
        #if canImport(ARKit) && !targetEnvironment(simulator)
        guard hasLidar else { return }
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal]
        if ARWorldTrackingConfiguration.supportsFrameSemantics([.sceneDepth, .smoothedSceneDepth]) {
            config.frameSemantics = [.sceneDepth, .smoothedSceneDepth]
        }
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
        }
        session.delegate = self
        session.run(config, options: [.resetTracking, .removeExistingAnchors])
        phase = .waitingForPlane
        statusText = Copy.Scan.findPlane
        #else
        phase = .unavailable
        #endif
    }

    func stop() {
        #if canImport(ARKit) && !targetEnvironment(simulator)
        session.pause()
        #endif
    }

    func resetMeasurement() {
        #if canImport(ARKit)
        cornerA = nil
        footprint = nil
        planeAnchor = nil
        #endif
        previewBox = nil
        lastCapturedBase64 = nil
        if hasLidar {
            phase = .waitingForPlane
            statusText = Copy.Scan.findPlane
        } else {
            phase = .unavailable
        }
    }

    func handleTap(screenPoint: CGPoint, viewSize: CGSize) {
        #if canImport(ARKit) && !targetEnvironment(simulator)
        guard hasLidar, let frame = session.currentFrame else { return }

        switch phase {
        case .waitingForPlane, .tapFirstCorner:
            if let hit = raycast(point: screenPoint, viewSize: viewSize, frame: frame, existingPlane: true) {
                planeAnchor = hit.anchor as? ARPlaneAnchor
                cornerA = hit.worldTransform.columns.3.xyz
                phase = .tapSecondCorner
                statusText = Copy.Scan.tapCorners
            }
        case .tapSecondCorner:
            guard let a = cornerA,
                  let hit = raycast(point: screenPoint, viewSize: viewSize, frame: frame, existingPlane: true)
            else { return }
            let b = hit.worldTransform.columns.3.xyz
            let origin = planeAnchor.map { SIMD3<Float>($0.transform.columns.3.x, $0.transform.columns.3.y, $0.transform.columns.3.z) } ?? a
            let normal = planeAnchor.map { SIMD3<Float>($0.transform.columns.1.x, $0.transform.columns.1.y, $0.transform.columns.1.z) } ?? SIMD3<Float>(0, 1, 0)
            let fp = MeasurementMath.footprint(cornerA: a, cornerB: b, planeOrigin: origin, planeNormal: normal)
            footprint = fp
            let height = estimateHeight(frame: frame, footprint: fp)
            finish(footprint: fp, heightM: height.heightM, sampleCount: height.sampleCount, frame: frame)
        case .refiningHeight, .preview:
            guard let fp = footprint,
                  let hit = raycast(point: screenPoint, viewSize: viewSize, frame: frame, existingPlane: false)
            else { return }
            let top = hit.worldTransform.columns.3.xyz
            let heightM = MeasurementMath.heightFromTopTap(topY: top.y, planeY: fp.planeOrigin.y)
            finish(footprint: fp, heightM: heightM, sampleCount: 40, frame: frame)
        case .unavailable:
            break
        }
        #endif
    }

    #if canImport(ARKit) && !targetEnvironment(simulator)
    private func raycast(
        point: CGPoint,
        viewSize: CGSize,
        frame: ARFrame,
        existingPlane: Bool
    ) -> ARRaycastResult? {
        let normalized = CGPoint(x: point.x / viewSize.width, y: point.y / viewSize.height)
        let query: ARRaycastQuery?
        if existingPlane {
            query = frame.raycastQuery(from: normalized, allowing: .existingPlaneGeometry, alignment: .horizontal)
        } else {
            query = frame.raycastQuery(from: normalized, allowing: .estimatedPlane, alignment: .any)
        }
        guard let query else { return nil }
        return session.raycast(query).first
    }

    private func estimateHeight(frame: ARFrame, footprint: MeasurementMath.Footprint) -> (heightM: Double, sampleCount: Int) {
        // Prefer mesh vertices inside footprint; fall back to smoothed depth grid.
        var samples: [Double] = []
        for anchor in session.currentFrame?.anchors ?? [] {
            guard let mesh = anchor as? ARMeshAnchor else { continue }
            let vertices = mesh.geometry.vertices
            let vertexCount = vertices.count
            for i in 0..<vertexCount {
                let ptr = vertices.buffer.contents().advanced(by: vertices.offset + vertices.stride * i)
                let local = ptr.assumingMemoryBound(to: (Float, Float, Float).self).pointee
                let localPos = SIMD4<Float>(local.0, local.1, local.2, 1)
                let world = mesh.transform * localPos
                let p = SIMD3<Float>(world.x, world.y, world.z)
                if insideFootprint(p, footprint) {
                    let height = Double(p.y - footprint.planeOrigin.y)
                    if height > 0 { samples.append(height) }
                }
            }
        }

        if samples.count < 20, let depth = frame.smoothedSceneDepth?.depthMap ?? frame.sceneDepth?.depthMap {
            samples.append(contentsOf: sampleDepthGrid(depth: depth, frame: frame, footprint: footprint))
        }

        return MeasurementMath.heightMeters(samplesAbovePlane: samples)
    }

    private func insideFootprint(_ p: SIMD3<Float>, _ fp: MeasurementMath.Footprint) -> Bool {
        let rel = p - fp.planeOrigin
        let x = Double(dot(rel, fp.localX))
        let z = Double(dot(rel, fp.localZ))
        return x >= 0 && x <= fp.widthM && z >= 0 && z <= fp.depthM
    }

    private func sampleDepthGrid(depth: CVPixelBuffer, frame: ARFrame, footprint: MeasurementMath.Footprint) -> [Double] {
        CVPixelBufferLockBaseAddress(depth, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depth, .readOnly) }
        let width = CVPixelBufferGetWidth(depth)
        let height = CVPixelBufferGetHeight(depth)
        guard let base = CVPixelBufferGetBaseAddress(depth) else { return [] }
        let bind = base.assumingMemoryBound(to: Float32.self)
        var out: [Double] = []
        let step = max(1, min(width, height) / 20)
        let intrinsics = frame.camera.intrinsics
        let view = frame.camera.viewMatrix(for: .portrait)
        for y in stride(from: 0, to: height, by: step) {
            for x in stride(from: 0, to: width, by: step) {
                let d = bind[y * width + x]
                guard d.isFinite, d > 0.1, d < 4 else { continue }
                // Approximate unproject in camera space then to world; good enough for height percentile.
                let fx = intrinsics[0, 0]
                let fy = intrinsics[1, 1]
                let cx = intrinsics[2, 0]
                let cy = intrinsics[2, 1]
                let xCam = (Float(x) - cx) * d / fx
                let yCam = (Float(y) - cy) * d / fy
                let cam = SIMD4<Float>(xCam, yCam, -d, 1)
                let world4 = view.inverse * cam
                let p = SIMD3<Float>(world4.x, world4.y, world4.z)
                if insideFootprint(p, footprint) {
                    let h = Double(p.y - footprint.planeOrigin.y)
                    if h > 0 { out.append(h) }
                }
            }
        }
        return out
    }

    private func finish(footprint: MeasurementMath.Footprint, heightM: Double, sampleCount: Int, frame: ARFrame) {
        let dims = MeasurementMath.dimsCm(widthM: footprint.widthM, heightM: heightM, depthM: footprint.depthM)
        let minSide = min(dims.w, dims.d)
        var lowConfidence = false
        if let conf = frame.smoothedSceneDepth?.confidenceMap ?? frame.sceneDepth?.confidenceMap {
            lowConfidence = meanConfidenceBelowMedium(conf)
        }
        let conf = MeasurementMath.confidence(
            meanDepthConfidenceBelowMedium: lowConfidence,
            footprintMinSideCm: minSide,
            heightSampleCount: sampleCount
        )
        let box = MeasuredBox(w: dims.w, h: dims.h, d: dims.d, confidence: conf, method: .lidar)
        previewBox = box
        phase = .preview(box)
        statusText = Copy.Scan.confirmBox
        if let cg = frame.capturedImage.cgImageCompat {
            lastCapturedBase64 = ImageCapture.jpegBase64(from: cg)
        }
    }

    private func meanConfidenceBelowMedium(_ map: CVPixelBuffer) -> Bool {
        CVPixelBufferLockBaseAddress(map, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(map, .readOnly) }
        let width = CVPixelBufferGetWidth(map)
        let height = CVPixelBufferGetHeight(map)
        guard let base = CVPixelBufferGetBaseAddress(map) else { return false }
        let ptr = base.assumingMemoryBound(to: UInt8.self)
        var sum = 0
        var count = 0
        let step = max(1, (width * height) / 200)
        for i in stride(from: 0, to: width * height, by: step) {
            sum += Int(ptr[i])
            count += 1
        }
        guard count > 0 else { return false }
        // ARConfidenceLevel: low=0, medium=1, high=2
        return Double(sum) / Double(count) < 1.0
    }
    #endif
}

#if canImport(ARKit) && !targetEnvironment(simulator)
extension LidarSessionController: ARSessionDelegate {
    nonisolated func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        Task { @MainActor in
            if planeAnchor == nil, anchors.contains(where: { $0 is ARPlaneAnchor }) {
                phase = .tapFirstCorner
                statusText = Copy.Scan.tapCorners
            }
        }
    }
}

private extension SIMD4 where Scalar == Float {
    var xyz: SIMD3<Float> { SIMD3(x, y, z) }
}

private extension CVPixelBuffer {
    var cgImageCompat: CGImage? {
        let ci = CIImage(cvPixelBuffer: self)
        return CIContext().createCGImage(ci, from: ci.extent)
    }
}
#endif
