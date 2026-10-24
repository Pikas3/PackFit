import RealityKit
import UIKit

@MainActor
enum CategoryMaterials {
    private struct Key: Hashable {
        var category: Category
        var opacityPercent: Int
    }

    private static var cache: [Key: SimpleMaterial] = [:]
    private static let sharedBox: MeshResource = .generateBox(size: 1)

    static func boxMesh() -> MeshResource { sharedBox }

    static func material(for category: Category, opacity: CGFloat = 1) -> SimpleMaterial {
        let key = Key(category: category, opacityPercent: Int((opacity * 100).rounded()))
        if let cached = cache[key] { return cached }
        let base = uiColor(for: category).withAlphaComponent(CGFloat(key.opacityPercent) / 100)
        let material = SimpleMaterial(color: base, roughness: 0.55, isMetallic: false)
        cache[key] = material
        return material
    }

    private static func uiColor(for category: Category) -> UIColor {
        switch category {
        case .clothing: return UIColor(red: 0.25, green: 0.45, blue: 0.85, alpha: 1)
        case .shoes: return UIColor(red: 0.45, green: 0.30, blue: 0.20, alpha: 1)
        case .toiletries: return UIColor(red: 0.30, green: 0.70, blue: 0.65, alpha: 1)
        case .liquids: return UIColor(red: 0.20, green: 0.55, blue: 0.90, alpha: 1)
        case .electronics: return UIColor(red: 0.35, green: 0.35, blue: 0.40, alpha: 1)
        case .documents: return UIColor(red: 0.90, green: 0.85, blue: 0.55, alpha: 1)
        case .medical: return UIColor(red: 0.85, green: 0.30, blue: 0.35, alpha: 1)
        case .food: return UIColor(red: 0.90, green: 0.55, blue: 0.20, alpha: 1)
        case .sharp: return UIColor(red: 0.70, green: 0.70, blue: 0.75, alpha: 1)
        case .other: return UIColor(red: 0.55, green: 0.55, blue: 0.60, alpha: 1)
        }
    }
}
