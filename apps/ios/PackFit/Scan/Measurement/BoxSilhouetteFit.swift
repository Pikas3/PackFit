import Foundation
import simd

/// Refines boxes on the floor so their projections match the observed outlines in every
/// view. The voxel hull gives the starting point and keeps other objects out; this stage
/// gives the size, because a box's outline from any pose is exact under perspective, while
/// the hull alone overshoots wherever no camera looked from the far side or from low down.
enum BoxSilhouetteFit {
    struct Result: Sendable, Equatable {
        var boxes: [BoxFit]
        /// Trimmed mean IoU between the boxes' outline and the observed one, 0-1.
        var score: Float
    }

    /// Coordinate descent over each box's centre, yaw, long, short and height. All boxes
    /// are drawn together, so two halves of an open suitcase fit one merged outline.
    /// `warm`: `initial` is already close (the previous fit), so the coarsest steps are skipped.
    static func refine(_ initial: [BoxFit], floorY: Float, views: [HullView], pixelStride: Int = 2, minHeight: Float = 0.004, warm: Bool = false) -> Result {
        let prepared = views.map(PreparedView.init)
        guard !initial.isEmpty, !prepared.isEmpty else { return Result(boxes: initial, score: 0) }
        var boxes = initial
        var best = score(boxes, floorY: floorY, views: prepared, stride: pixelStride)

        // (centre m, yaw rad, size m, height m), halved twice.
        var steps: (c: Float, yaw: Float, s: Float, h: Float) = warm ? (0.005, 0.025, 0.005, 0.0025) : (0.01, 0.05, 0.01, 0.005)
        for _ in 0..<(warm ? 2 : 3) {
            var improved = true
            var rounds = 0
            while improved, rounds < 12 {
                improved = false
                rounds += 1
                for b in boxes.indices {
                    for param in 0..<6 {
                        for sign: Float in [1, -1] {
                            var trial = boxes
                            var box = trial[b]
                            switch param {
                            case 0: box.rect.center.x += sign * steps.c
                            case 1: box.rect.center.y += sign * steps.c
                            case 2: box.rect.yaw = OrientedRect.normalizedYaw(box.rect.yaw + sign * steps.yaw)
                            case 3: box.rect.long = max(box.rect.long + sign * steps.s, 0.01)
                            case 4: box.rect.short = max(box.rect.short + sign * steps.s, 0.01)
                            default: box.height = max(box.height + sign * steps.h, minHeight)
                            }
                            trial[b] = box
                            let s = score(trial, floorY: floorY, views: prepared, stride: pixelStride)
                            if s > best + 1e-5 {
                                best = s
                                boxes = trial
                                improved = true
                                break
                            }
                        }
                    }
                }
            }
            steps = (steps.c / 2, steps.yaw / 2, steps.s / 2, steps.h / 2)
        }
        for i in boxes.indices where boxes[i].rect.short > boxes[i].rect.long {
            var r = boxes[i].rect
            swap(&r.long, &r.short)
            r.yaw = OrientedRect.normalizedYaw(r.yaw + .pi / 2)
            boxes[i].rect = r
        }
        return Result(boxes: boxes, score: best)
    }

    /// A view with its mask's bounding box, so scoring only walks the pixels that matter.
    struct PreparedView {
        let view: HullView
        let toCamera: simd_float4x4
        /// Nil when the outline is empty or runs off the image (cut off, so not comparable).
        let maskBox: (u0: Int, v0: Int, u1: Int, v1: Int)?

        init(_ view: HullView) {
            self.view = view
            toCamera = view.cameraToWorld.inverse
            var u0 = Int.max, v0 = Int.max, u1 = -1, v1 = -1
            for v in 0..<view.height {
                for u in 0..<view.width where view.mask[v * view.width + u] {
                    u0 = min(u0, u); u1 = max(u1, u); v0 = min(v0, v); v1 = max(v1, v)
                }
            }
            let clipped = u0 == 0 || v0 == 0 || u1 == view.width - 1 || v1 == view.height - 1
            maskBox = u1 >= 0 && !clipped ? (u0, v0, u1, v1) : nil
        }

        func project(_ p: SIMD3<Float>) -> SIMD2<Float>? {
            let c = toCamera * SIMD4(p, 1)
            let d = -c.z
            guard d > 0.05 else { return nil }
            return [c.x * view.fx / d + view.cx, -c.y * view.fy / d + view.cy]
        }
    }

    /// Trimmed mean IoU over views: the worst fifth is dropped, so a few bad masks
    /// (occlusion, segmentation flicker) don't pull the boxes.
    static func score(_ boxes: [BoxFit], floorY: Float, views: [PreparedView], stride: Int) -> Float {
        var ious: [Float] = []
        ious.reserveCapacity(views.count)
        for pv in views {
            guard let iou = iou(boxes, floorY: floorY, view: pv, stride: stride) else { continue }
            ious.append(iou)
        }
        guard !ious.isEmpty else { return 0 }
        ious.sort()
        let drop = ious.count >= 5 ? ious.count / 5 : 0
        let kept = ious[drop...]
        return kept.reduce(0, +) / Float(kept.count)
    }

    static func iou(_ boxes: [BoxFit], floorY: Float, view pv: PreparedView, stride: Int) -> Float? {
        guard let maskBox = pv.maskBox else { return nil }
        var polys: [[SIMD2<Float>]] = []
        var u0 = maskBox.u0, v0 = maskBox.v0, u1 = maskBox.u1, v1 = maskBox.v1
        for box in boxes {
            var pts: [SIMD2<Float>] = []
            for c in box.rect.corners {
                for y in [floorY, floorY + box.height] {
                    guard let p = pv.project([c.x, y, c.y]) else { return nil }
                    pts.append(p)
                }
            }
            let hull = RectFit.convexHull(pts)
            for p in hull {
                u0 = min(u0, Int(p.x)); u1 = max(u1, Int(p.x))
                v0 = min(v0, Int(p.y)); v1 = max(v1, Int(p.y))
            }
            polys.append(hull)
        }
        let w = pv.view.width, h = pv.view.height
        u0 = max(u0 - 1, 0); v0 = max(v0 - 1, 0); u1 = min(u1 + 1, w - 1); v1 = min(v1 + 1, h - 1)
        var inter = 0, union = 0
        var v = v0
        while v <= v1 {
            var u = u0
            let py = Float(v) + 0.5
            while u <= u1 {
                let p = SIMD2(Float(u) + 0.5, py)
                let m = pv.view.mask[v * w + u]
                let b = polys.contains { inConvex(p, $0) }
                if m && b { inter += 1 }
                if m || b { union += 1 }
                u += stride
            }
            v += stride
        }
        return union > 0 ? Float(inter) / Float(union) : nil
    }

    /// Point in a counter-clockwise convex polygon.
    @inline(__always) static func inConvex(_ p: SIMD2<Float>, _ poly: [SIMD2<Float>]) -> Bool {
        guard poly.count >= 3 else { return false }
        var j = poly.count - 1
        for i in poly.indices {
            let a = poly[j], b = poly[i]
            if (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x) < 0 { return false }
            j = i
        }
        return true
    }
}
