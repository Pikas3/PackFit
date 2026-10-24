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

        let fill = UnlitMaterial(color: UIColor.white.withAlphaComponent(0.08))
        let volume = ModelEntity(mesh: .generateBox(size: [w, h, d]), materials: [fill])
        volume.position = [w / 2, h / 2, d / 2]
        root.addChild(volume)

        for edge in edgeEntities(size: [w, h, d], color: UIColor.white.withAlphaComponent(0.55), thickness: 0.003) {
            root.addChild(edge)
        }

        let lid = ModelEntity(
            mesh: .generatePlane(width: w * 0.98, depth: d * 0.98),
            materials: [UnlitMaterial(color: UIColor.systemTeal.withAlphaComponent(0.35))]
        )
        lid.position = [w / 2, h, d / 2]
        lid.orientation = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])
        lid.name = type == .backpack ? "opening-top" : "opening-lid"
        root.addChild(lid)

        return root
    }

    @MainActor
    static func buildItemEntity(placement: Placement, item: Item) -> ModelEntity {
        let size = SIMD3<Float>(
            Float(placement.w) * cmToMeters,
            Float(placement.h) * cmToMeters,
            Float(placement.d) * cmToMeters
        )
        let entity = ModelEntity(
            mesh: CategoryMaterials.boxMesh(),
            materials: [CategoryMaterials.material(for: item.category)]
        )
        entity.scale = size
        entity.position = [
            Float(placement.x) * cmToMeters + size.x / 2,
            Float(placement.y) * cmToMeters + size.y / 2,
            Float(placement.z) * cmToMeters + size.z / 2
        ]
        entity.name = placement.itemId
        entity.generateCollisionShapes(recursive: false)

        if item.fragile {
            let frameRoot = Entity()
            frameRoot.name = "fragile-frame"
            // Edges in local space where the unit box is centered at origin, then match parent scale.
            for edge in edgeEntities(size: [1.06, 1.06, 1.06], color: .systemRed, thickness: 0.04) {
                frameRoot.addChild(edge)
            }
            entity.addChild(frameRoot)
        }
        return entity
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
