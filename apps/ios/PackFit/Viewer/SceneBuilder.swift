import RealityKit
import UIKit
import simd

enum SceneBuilder {
    static let cmToMeters: Float = 0.01

    @MainActor
    static func buildContainer(outer: [Double], type: ContainerType) -> Entity {
        let root = Entity()
        root.name = "container"

        let w = Float(outer[0]) * cmToMeters
        let h = Float(outer[1]) * cmToMeters
        let d = Float(outer[2]) * cmToMeters

        // Both see-through surfaces share a sort group so the lid always draws after the
        // volume; otherwise the renderer flips their order as the camera orbits.
        let sortGroup = ModelSortGroup(depthPass: nil)

        let fill = translucent(.white, opacity: 0.08)
        let volume = ModelEntity(mesh: .generateBox(size: [w, h, d]), materials: [fill])
        volume.position = [w / 2, h / 2, d / 2]
        volume.components.set(ModelSortGroupComponent(group: sortGroup, order: 0))
        root.addChild(volume)

        for edge in edgeEntities(size: [w, h, d], color: UIColor.white.withAlphaComponent(0.55), thickness: 0.003) {
            root.addChild(edge)
        }

        let lid = ModelEntity(
            mesh: .generatePlane(width: w * 0.98, depth: d * 0.98),
            materials: [translucent(.systemTeal, opacity: 0.15)]
        )
        // generatePlane(width:depth:) already lies flat in XZ. Lifted 2 mm off the volume's
        // top face so the two never share a depth.
        lid.position = [w / 2, h + 0.002, d / 2]
        lid.components.set(ModelSortGroupComponent(group: sortGroup, order: 1))
        lid.name = type == .backpack ? "opening-top" : "opening-lid"
        root.addChild(lid)

        return root
    }

    /// Placement axis a cylinder runs along: the one whose other two sides are closest, since
    /// those are both the diameter. 0 = x, 1 = y, 2 = z; ties go to y (standing).
    static func cylinderAxis(_ size: SIMD3<Float>) -> Int {
        let spread: [(axis: Int, diff: Float)] = [
            (1, abs(size.x - size.z)), (0, abs(size.y - size.z)), (2, abs(size.x - size.y)),
        ]
        return spread.min { $0.diff < $1.diff }!.axis
    }

    /// Placement axis the item's own top (its scanned `h`) ended up on. Soft items may be
    /// pressed down by the packer, so the vertical axis also matches a compressed height.
    static func topAxis(placement: Placement, item: Item) -> Int {
        let close = { (a: Double, b: Double) in abs(a - b) < 0.05 }
        if close(placement.h, item.h) || (item.soft && placement.h < item.h && close(placement.w * placement.d, item.w * item.d)) {
            return 1
        }
        if close(placement.w, item.h) { return 0 }
        if close(placement.d, item.h) { return 2 }
        return 1
    }

    /// One item as its built-in model, scaled to the placement. The returned entity is the
    /// unit cube (its scale is the size) so the stepper can pulse and fade it as one piece.
    @MainActor
    static func buildItemEntity(placement: Placement, item: Item, shape: ObjectShape? = nil) -> ModelEntity {
        let size = SIMD3<Float>(
            Float(placement.w) * cmToMeters,
            Float(placement.h) * cmToMeters,
            Float(placement.d) * cmToMeters
        )
        let kind = ItemModels.kind(for: item, shape: shape)
        let entity = ModelEntity()
        entity.addChild(ItemModels.build(kind, category: item.category))

        // Models are built with their top along local y. Turn local y onto the right axis
        // and swap the scale so the world-space size is still w x h x d.
        let axis = kind.isRound ? cylinderAxis(size) : topAxis(placement: placement, item: item)
        switch axis {
        case 0:
            entity.orientation = simd_quatf(angle: -.pi / 2, axis: [0, 0, 1])
            entity.scale = [size.y, size.x, size.z]
        case 2:
            entity.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
            entity.scale = [size.x, size.z, size.y]
        default:
            entity.scale = size
        }
        entity.position = [
            Float(placement.x) * cmToMeters + size.x / 2,
            Float(placement.y) * cmToMeters + size.y / 2,
            Float(placement.z) * cmToMeters + size.z / 2
        ]
        entity.name = placement.itemId
        entity.components.set(CollisionComponent(shapes: [.generateBox(size: [1, 1, 1])]))

        if item.fragile {
            entity.addChild(fragileFrame(localScale: entity.scale))
        }
        return entity
    }

    /// Red outline just outside the item's unit cube. Thickness is divided by the parent's
    /// scale per axis so the lines are the same width on a flat laptop and a tall bottle.
    @MainActor
    static func fragileFrame(localScale s: SIMD3<Float>, thickness: Float = 0.004, margin: Float = 0.004) -> Entity {
        let t = SIMD3<Float>(thickness / s.x, thickness / s.y, thickness / s.z)
        let half = SIMD3<Float>(0.5 + margin / s.x, 0.5 + margin / s.y, 0.5 + margin / s.z)
        let mat = UnlitMaterial(color: .systemRed)
        let mesh = MeshResource.generateBox(size: 1)
        let frame = Entity()
        frame.name = "fragile-frame"
        for axis in 0..<3 {
            let u = (axis + 1) % 3, v = (axis + 2) % 3
            for su: Float in [-1, 1] {
                for sv: Float in [-1, 1] {
                    var center = SIMD3<Float>(repeating: 0)
                    center[u] = su * half[u]
                    center[v] = sv * half[v]
                    var scale = t
                    scale[axis] = half[axis] * 2 + t[axis]
                    let edge = ModelEntity(mesh: mesh, materials: [mat])
                    edge.position = center
                    edge.scale = scale
                    frame.addChild(edge)
                }
            }
        }
        return frame
    }

    /// The current item's name, always facing the camera, centred on its anchor.
    @MainActor
    static func buildLabel(_ text: String) -> Entity {
        let mesh = MeshResource.generateText(
            text, extrusionDepth: 0.001, font: .systemFont(ofSize: 0.025, weight: .semibold),
            containerFrame: .zero, alignment: .center, lineBreakMode: .byTruncatingTail
        )
        let textEntity = ModelEntity(mesh: mesh, materials: [UnlitMaterial(color: .white)])
        textEntity.position = -mesh.bounds.center
        let bounds = mesh.bounds.extents
        let backing = ModelEntity(
            mesh: .generatePlane(width: bounds.x + 0.016, height: bounds.y + 0.01, cornerRadius: 0.005),
            materials: [translucent(.black, opacity: 0.55)]
        )
        backing.position = [0, 0, -0.001]
        let tag = Entity()
        tag.name = "label"
        tag.addChild(backing)
        tag.addChild(textEntity)
        tag.components.set(BillboardComponent())
        return tag
    }

    /// Unlit colour with real alpha blending; a colour's alpha alone renders opaque.
    @MainActor
    static func translucent(_ color: UIColor, opacity: Float) -> UnlitMaterial {
        var material = UnlitMaterial(color: color)
        material.blending = .transparent(opacity: .init(floatLiteral: opacity))
        return material
    }

    @MainActor
    static func edgeEntities(size: SIMD3<Float>, color: UIColor, thickness: Float) -> [ModelEntity] {
        let mat = UnlitMaterial(color: color)
        let mesh = MeshResource.generateBox(size: 1)
        let w = size.x, h = size.y, d = size.z
        let t = thickness

        struct Edge { var center: SIMD3<Float>; var scale: SIMD3<Float> }
        let edges: [Edge] = [
            .init(center: [w / 2, 0, 0], scale: [w, t, t]),
            .init(center: [w / 2, 0, d], scale: [w, t, t]),
            .init(center: [0, 0, d / 2], scale: [t, t, d]),
            .init(center: [w, 0, d / 2], scale: [t, t, d]),
            .init(center: [w / 2, h, 0], scale: [w, t, t]),
            .init(center: [w / 2, h, d], scale: [w, t, t]),
            .init(center: [0, h, d / 2], scale: [t, t, d]),
            .init(center: [w, h, d / 2], scale: [t, t, d]),
            .init(center: [0, h / 2, 0], scale: [t, h, t]),
            .init(center: [w, h / 2, 0], scale: [t, h, t]),
            .init(center: [0, h / 2, d], scale: [t, h, t]),
            .init(center: [w, h / 2, d], scale: [t, h, t])
        ]

        return edges.map { edge in
            let e = ModelEntity(mesh: mesh, materials: [mat])
            e.scale = edge.scale
            e.position = edge.center
            return e
        }
    }
}
