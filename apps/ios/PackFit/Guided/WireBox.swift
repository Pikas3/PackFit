import Foundation
import simd
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// A live wireframe box in world space, drawn by projecting its corners onto the camera preview.
struct LiveWire: Identifiable, Equatable, Sendable {
    let id: String
    var size: SIMD3<Float>
    /// Places the box centre in world coordinates.
    var transform: simd_float4x4
    var color: SIMD4<Float>
    var label: String?

    static func transform(for fit: BoxFit, floorY: Float) -> simd_float4x4 {
        var m = simd_float4x4(simd_quatf(angle: -fit.rect.yaw, axis: [0, 1, 0]))
        m.columns.3 = SIMD4(fit.rect.center.x, floorY + fit.height / 2, fit.rect.center.y, 1)
        return m
    }

    /// Eight corners in world space.
    var corners: [SIMD3<Float>] {
        let h = size / 2
        let locals: [SIMD3<Float>] = [
            [-h.x, -h.y, -h.z], [h.x, -h.y, -h.z], [h.x, -h.y, h.z], [-h.x, -h.y, h.z],
            [-h.x, h.y, -h.z], [h.x, h.y, -h.z], [h.x, h.y, h.z], [-h.x, h.y, h.z],
        ]
        return locals.map { p in
            let w = transform * SIMD4(p.x, p.y, p.z, 1)
            return SIMD3(w.x, w.y, w.z)
        }
    }

    static func rgba(_ color: Color, opacity: Double = 1) -> SIMD4<Float> {
        #if canImport(UIKit)
        let ui = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return SIMD4(Float(r), Float(g), Float(b), Float(a * opacity))
        #else
        return SIMD4(0, 1, 0, Float(opacity))
        #endif
    }
}

enum WireColors {
    static let stable = SIMD4<Float>(0.2, 0.8, 0.3, 0.95)
    static let measuring = SIMD4<Float>(1.0, 0.8, 0.1, 0.95)
    static let locked = SIMD4<Float>(1, 1, 1, 0.7)
    static let draft = SIMD4<Float>(1.0, 0.8, 0.1, 0.95)
}
