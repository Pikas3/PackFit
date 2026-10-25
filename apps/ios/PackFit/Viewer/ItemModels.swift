import RealityKit
import UIKit

/// Built-in models, one per kind of item, in a single flat-shaded style so every bag looks
/// consistent. Each model fills the unit cube [-0.5, 0.5]³ with its natural top along +y;
/// `SceneBuilder` scales and turns it onto the item's placement.
@MainActor
enum ItemModels {
    enum Kind: CaseIterable {
        case bottle, can, tube, laptop, phone, book, clothing, shoes, pouch, medkit,
             headphones, camera, glasses, box

        /// Round kinds whose axis follows the cylinder's, not the item's scanned height.
        var isRound: Bool { self == .bottle || self == .can || self == .tube }
    }

    // MARK: Picking a kind

    /// Name words checked in order; the first kind with a match wins.
    private static let words: [(Kind, [String])] = [
        (.laptop, ["laptop", "macbook", "chromebook"]),
        (.phone, ["phone", "iphone", "smartphone", "tablet", "ipad", "kindle", "ereader"]),
        (.headphones, ["headphone", "headphones", "headset"]),
        (.camera, ["camera"]),
        (.glasses, ["glasses", "sunglasses", "spectacles"]),
        (.tube, ["tube", "toothpaste", "deodorant", "spray", "sunscreen", "chapstick", "lipstick", "lipbalm"]),
        (.bottle, ["bottle", "flask", "thermos", "tumbler", "shampoo", "conditioner", "lotion"]),
        (.can, ["can", "jar", "cup", "mug", "candle", "tin"]),
        (.shoes, ["shoe", "sneaker", "boot", "sandal", "slipper", "trainer", "heel", "loafer"]),
        (.clothing, ["shirt", "tshirt", "tee", "jeans", "pants", "trousers", "sweater", "jumper",
                     "hoodie", "jacket", "coat", "dress", "shorts", "sock", "underwear", "towel",
                     "scarf", "skirt", "pyjamas", "pajamas", "leggings", "top", "blouse", "clothes"]),
        (.book, ["book", "notebook", "passport", "journal", "magazine", "folder", "documents", "diary"]),
        (.medkit, ["firstaid", "medicine", "medication", "pills"]),
        (.pouch, ["bag", "pouch", "kit", "wallet", "case", "toiletry", "toiletries", "washbag"]),
    ]

    static func kind(for item: Item, shape: ObjectShape?) -> Kind {
        // "T-shirt" → "tshirt", "first aid" → "firstaid".
        let name = item.name.lowercased()
        var tokens = name.split { !$0.isLetter }.map(String.init)
        tokens.append(name.filter(\.isLetter))
        let matches = { (word: String) in
            tokens.contains { $0 == word || $0 == word + "s" || $0 == word + "es" }
        }
        var kind = words.first { $0.1.contains(where: matches) }?.0 ?? fallback(item.category)

        // The photo scan saw a cylinder: keep a round kind, or make it one.
        if shape == .uprightCylinder || shape == .lyingCylinder, !kind.isRound {
            kind = item.category == .liquids ? .bottle : .can
        }
        return kind
    }

    private static func fallback(_ category: Category) -> Kind {
        switch category {
        case .clothing: .clothing
        case .shoes: .shoes
        case .toiletries: .pouch
        case .liquids: .bottle
        case .documents: .book
        case .medical: .medkit
        case .electronics, .food, .sharp, .other: .box
        }
    }

    // MARK: Building

    static func build(_ kind: Kind, category: Category) -> Entity {
        let root = Entity()
        let base = CategoryMaterials.uiColor(for: category)
        let p = Palette(base: base)
        func add(_ part: ModelEntity) { root.addChild(part) }

        switch kind {
        case .bottle:
            add(cylinder(p.base, center: [0, -0.12, 0], radius: 0.5, height: 0.76))
            add(cylinder(p.light, center: [0, -0.1, 0], radius: 0.505, height: 0.28))   // label
            add(cylinder(p.base, center: [0, 0.3, 0], radius: 0.38, height: 0.08))     // shoulder
            add(cylinder(p.base, center: [0, 0.37, 0], radius: 0.24, height: 0.08))    // neck
            add(cylinder(p.dark, center: [0, 0.45, 0], radius: 0.27, height: 0.1))     // cap
        case .can:
            add(cylinder(p.base, center: [0, 0, 0], radius: 0.5, height: 0.86))
            add(cylinder(p.metal, center: [0, 0.46, 0], radius: 0.46, height: 0.08))
            add(cylinder(p.metal, center: [0, -0.46, 0], radius: 0.46, height: 0.08))
            add(cylinder(p.light, center: [0, 0.05, 0], radius: 0.505, height: 0.3))
        case .tube:
            add(cylinder(p.base, center: [0, -0.12, 0], radius: 0.5, height: 0.76))
            add(cylinder(p.dark, center: [0, 0.38, 0], radius: 0.46, height: 0.24))   // cap
        case .laptop:
            add(box(p.metal, center: [0, -0.23, 0], size: [1, 0.54, 1], corner: 0.06))
            add(box(p.charcoal, center: [0, 0.03, 0], size: [0.98, 0.04, 0.98]))         // seam
            add(box(p.metal, center: [0, 0.27, 0], size: [1, 0.46, 1], corner: 0.06))
            add(box(p.light, center: [0, 0.5, 0], size: [0.18, 0.01, 0.18], corner: 0.04)) // logo
        case .phone:
            add(box(p.charcoal, center: .zero, size: [1, 1, 1], corner: 0.12))
            add(box(p.screen, center: [0, 0.5, 0], size: [0.9, 0.02, 0.93], corner: 0.08))
        case .book:
            add(box(p.base, center: [0, 0.45, 0], size: [1, 0.1, 1]))                    // covers
            add(box(p.base, center: [0, -0.45, 0], size: [1, 0.1, 1]))
            add(box(p.dark, center: [-0.47, 0, 0], size: [0.06, 1, 1]))                  // spine
            add(box(p.paper, center: [0.02, 0, 0], size: [0.92, 0.82, 0.96]))            // pages
        case .clothing:
            // Folded stack: three soft layers, slightly offset.
            add(box(p.base, center: [0, -0.33, 0], size: [1, 0.34, 1], corner: 0.12))
            add(box(p.light, center: [0.01, 0, -0.01], size: [0.97, 0.34, 0.98], corner: 0.12))
            add(box(p.base, center: [-0.01, 0.33, 0.01], size: [0.95, 0.34, 0.96], corner: 0.12))
        case .shoes:
            add(box(p.paper, center: [0, -0.41, 0], size: [1, 0.18, 1], corner: 0.06))     // sole
            add(box(p.base, center: [-0.17, 0.05, 0], size: [0.66, 0.74, 0.92], corner: 0.2)) // upper
            add(box(p.base, center: [0.27, -0.12, 0], size: [0.46, 0.42, 0.86], corner: 0.2)) // toe
            add(box(p.charcoal, center: [-0.24, 0.42, 0], size: [0.36, 0.02, 0.6], corner: 0.01)) // opening
        case .pouch:
            add(box(p.base, center: [0, -0.05, 0], size: [1, 0.9, 1], corner: 0.25))
            add(box(p.dark, center: [0, 0.4, 0], size: [0.9, 0.03, 0.06]))              // zip
            add(box(p.metal, center: [0.3, 0.42, 0.06], size: [0.08, 0.03, 0.12]))       // pull
        case .medkit:
            add(box(p.base, center: .zero, size: [1, 1, 1], corner: 0.12))
            add(box(p.paper, center: [0, 0.5, 0], size: [0.5, 0.02, 0.14]))
            add(box(p.paper, center: [0, 0.5, 0], size: [0.14, 0.02, 0.5]))
        case .headphones:
            add(cylinder(p.charcoal, center: [-0.37, -0.15, 0], radius: 0.4, height: 0.26, axis: 0))
            add(cylinder(p.charcoal, center: [0.37, -0.15, 0], radius: 0.4, height: 0.26, axis: 0))
            add(box(p.base, center: [0, 0.44, 0], size: [0.9, 0.12, 0.26], corner: 0.05))  // band
            add(box(p.base, center: [-0.43, 0.2, 0], size: [0.08, 0.5, 0.2]))
            add(box(p.base, center: [0.43, 0.2, 0], size: [0.08, 0.5, 0.2]))
        case .camera:
            add(box(p.charcoal, center: [0, -0.1, -0.15], size: [1, 0.8, 0.7], corner: 0.08))
            add(cylinder(p.metal, center: [0, -0.1, 0.32], radius: 0.3, height: 0.36, axis: 2))
            add(cylinder(p.screen, center: [0, -0.1, 0.5], radius: 0.22, height: 0.02, axis: 2))
            add(box(p.metal, center: [0.3, 0.35, -0.2], size: [0.14, 0.1, 0.14]))       // button
        case .glasses:
            add(box(p.charcoal, center: [0, 0.1, 0.45], size: [1, 0.22, 0.08], corner: 0.03)) // frame
            add(cylinder(p.screen, center: [-0.24, 0.1, 0.46], radius: 0.22, height: 0.06, axis: 2))
            add(cylinder(p.screen, center: [0.24, 0.1, 0.46], radius: 0.22, height: 0.06, axis: 2))
            add(box(p.charcoal, center: [-0.47, 0.15, -0.02], size: [0.05, 0.08, 0.92]))  // arms
            add(box(p.charcoal, center: [0.47, 0.15, -0.02], size: [0.05, 0.08, 0.92]))
        case .box:
            add(box(p.base, center: .zero, size: [1, 1, 1], corner: 0.06))
            add(box(p.light, center: [0, 0.5, 0], size: [0.86, 0.01, 0.86], corner: 0.04))
        }
        return root
    }

    // MARK: Parts

    private struct Palette {
        let base: UIColor
        var light: UIColor { base.mixed(with: .white, by: 0.35) }
        var dark: UIColor { base.mixed(with: .black, by: 0.4) }
        let charcoal = UIColor(white: 0.18, alpha: 1)
        let metal = UIColor(white: 0.72, alpha: 1)
        let paper = UIColor(white: 0.94, alpha: 1)
        let screen = UIColor(red: 0.08, green: 0.1, blue: 0.14, alpha: 1)
    }

    private static let unitBox = MeshResource.generateBox(size: 1)
    private static let unitCylinder = MeshResource.generateCylinder(height: 1, radius: 0.5)
    private static var roundedBoxes: [Int: MeshResource] = [:]
    private static var materials: [UIColor: SimpleMaterial] = [:]

    private static func material(_ color: UIColor) -> SimpleMaterial {
        if let cached = materials[color] { return cached }
        let m = SimpleMaterial(color: color, roughness: 0.6, isMetallic: false)
        materials[color] = m
        return m
    }

    /// `corner` is the edge radius in the model's unit cube.
    private static func box(_ color: UIColor, center: SIMD3<Float>, size: SIMD3<Float>, corner: Float = 0) -> ModelEntity {
        var mesh = unitBox
        if corner > 0 {
            let key = Int((corner * 100).rounded())
            mesh = roundedBoxes[key] ?? {
                let m = MeshResource.generateBox(size: 1, cornerRadius: Float(key) / 100)
                roundedBoxes[key] = m
                return m
            }()
        }
        let part = ModelEntity(mesh: mesh, materials: [material(color)])
        part.position = center
        part.scale = size
        return part
    }

    /// Cylinder along `axis` (0 = x, 1 = y, 2 = z).
    private static func cylinder(
        _ color: UIColor, center: SIMD3<Float>, radius: Float, height: Float, axis: Int = 1
    ) -> ModelEntity {
        let part = ModelEntity(mesh: unitCylinder, materials: [material(color)])
        part.position = center
        part.scale = [radius * 2, height, radius * 2]
        switch axis {
        case 0: part.orientation = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
        case 2: part.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        default: break
        }
        return part
    }
}

private extension UIColor {
    func mixed(with other: UIColor, by t: CGFloat) -> UIColor {
        var (r1, g1, b1, a1): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        var (r2, g2, b2, a2): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return UIColor(red: r1 + (r2 - r1) * t, green: g1 + (g2 - g1) * t,
                       blue: b1 + (b2 - b1) * t, alpha: a1 + (a2 - a1) * t)
    }
}
