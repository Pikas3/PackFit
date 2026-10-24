import RealityKit
import UIKit
import simd

/// A reusable 12-edge box outline whose local origin is the box centre. Resized in place so
/// live fits don't rebuild entities every tick.
@MainActor
final class WireBox {
    let entity = Entity()
    private let edges: [ModelEntity]
    private let hitBox = Entity()
    private var label: Entity?
    private var color: UIColor = .clear

    init(name: String) {
        entity.name = name
        let mesh = CategoryMaterials.boxMesh()
        edges = (0..<12).map { _ in ModelEntity(mesh: mesh, materials: []) }
        edges.forEach { entity.addChild($0) }
        hitBox.name = name
        entity.addChild(hitBox)
    }

    /// `transform` places the box centre; `size` is (x, y, z) in metres.
    func update(size: SIMD3<Float>, transform: simd_float4x4, color: UIColor, thickness: Float = 0.004) {
        entity.transform = Transform(matrix: transform)
        let h = size / 2, t = thickness
        var i = 0
        // Four edges along each axis.
        for (axis, a, b) in [(0, 1, 2), (1, 0, 2), (2, 0, 1)] {
            for sa: Float in [-1, 1] {
                for sb: Float in [-1, 1] {
                    var p = SIMD3<Float>.zero, s = SIMD3<Float>(repeating: t)
                    p[a] = sa * h[a]
                    p[b] = sb * h[b]
                    s[axis] = size[axis] + t
                    edges[i].position = p
                    edges[i].scale = s
                    i += 1
                }
            }
        }
        if color != self.color {
            self.color = color
            let material = UnlitMaterial(color: color)
            edges.forEach { $0.model?.materials = [material] }
        }
        hitBox.components.set(CollisionComponent(shapes: [.generateBox(size: size)]))
        label?.position = [0, h.y + 0.03, 0]
    }

    func setLabel(_ text: String) {
        label?.removeFromParent()
        let mesh = MeshResource.generateText(text, extrusionDepth: 0.001, font: .systemFont(ofSize: 0.04, weight: .bold), alignment: .center)
        let l = ModelEntity(mesh: mesh, materials: [UnlitMaterial(color: .white)])
        let bounds = mesh.bounds.extents
        let holder = Entity()
        holder.components.set(BillboardComponent())
        holder.addChild(l)
        l.position = [-bounds.x / 2, 0, 0]
        entity.addChild(holder)
        label = holder
    }

    /// World transform for a floor box: centred on the fit, rotated by its yaw.
    static func transform(for fit: BoxFit, floorY: Float) -> simd_float4x4 {
        var m = simd_float4x4(simd_quatf(angle: -fit.rect.yaw, axis: [0, 1, 0]))
        m.columns.3 = SIMD4(fit.rect.center.x, floorY + fit.height / 2, fit.rect.center.y, 1)
        return m
    }
}
