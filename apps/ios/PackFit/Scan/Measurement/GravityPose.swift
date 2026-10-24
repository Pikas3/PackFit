import CoreMotion
import Foundation
import simd

/// Gravity-aligned camera pose for AVFoundation LiDAR (no ARKit world tracking).
/// World frame: y up (against gravity), x/z horizontal. Camera sits at the origin;
/// hold still while measuring so the height map does not smear.
@MainActor
final class GravityPose {
    private let motion = CMMotionManager()
    private var rotation = matrix_identity_float3x3

    func start() {
        guard motion.isDeviceMotionAvailable else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 60.0
        // xArbitraryZVertical: z is gravity; remapped to y-up below.
        motion.startDeviceMotionUpdates(using: .xArbitraryZVertical)
    }

    func stop() {
        motion.stopDeviceMotionUpdates()
    }

    /// Camera-to-world for the current attitude. Translation is always the identity origin.
    func cameraToWorld() -> simd_float4x4 {
        if let dm = motion.deviceMotion {
            let r = dm.attitude.rotationMatrix
            // Columns of the device-to-reference rotation.
            let deviceToRef = simd_float3x3(
                SIMD3(Float(r.m11), Float(r.m21), Float(r.m31)),
                SIMD3(Float(r.m12), Float(r.m22), Float(r.m32)),
                SIMD3(Float(r.m13), Float(r.m23), Float(r.m33))
            )
            // Reference has +z up; packer/AR world uses +y up.
            let refToYUp = simd_float3x3(
                SIMD3(1, 0, 0),
                SIMD3(0, 0, 1),
                SIMD3(0, -1, 0)
            )
            rotation = refToYUp * deviceToRef
        }
        // AVFoundation camera: +x right, +y down, +z forward.
        // DepthSnapshot local: +x right, +y up, +z backward (ARKit-like).
        let avToLocal = simd_float3x3(
            SIMD3(1, 0, 0),
            SIMD3(0, -1, 0),
            SIMD3(0, 0, -1)
        )
        let R = rotation * avToLocal
        return simd_float4x4(
            SIMD4(R.columns.0, 0),
            SIMD4(R.columns.1, 0),
            SIMD4(R.columns.2, 0),
            SIMD4(0, 0, 0, 1)
        )
    }
}
