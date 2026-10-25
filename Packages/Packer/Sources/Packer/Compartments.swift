import PackFitSchemas

let mainCompartment = "main"

extension Compartment {
    var size: Size { Size(w: dims[0], h: dims[1], d: dims[2]) }
}

/// The compartment a placement lives in. `nil` means "main"; a container with no
/// compartment called "main" uses its first compartment for `nil`.
func compartment(named name: String?, in container: Container) -> Compartment? {
    guard let name else {
        return container.compartments.first { $0.name == mainCompartment } ?? container.compartments.first
    }
    return container.compartments.first { $0.name == name }
}

func compartmentName(_ p: Placement) -> String { p.compartment ?? mainCompartment }

func sameCompartment(_ a: Placement, _ b: Placement) -> Bool {
    compartmentName(a) == compartmentName(b)
}

/// Rule 9. Backpack `laptop` takes rigid electronics only; `front` takes items whose
/// smallest dimension is under 8 cm; every other compartment takes anything.
func accepts(_ compartment: Compartment, item: Item, container: Container) -> Bool {
    guard container.type == .backpack else { return true }
    switch compartment.name {
    case "laptop": return item.category == .electronics && item.hardness >= 0.7 - eps
    case "front": return min(item.w, item.h, item.d) < 8 - eps
    default: return true
    }
}

/// Restricted compartments are filled first (laptop, then front) so they get the items
/// they exist for; the rest go to the remaining compartments in container order.
/// Zipper suitcases fill the base (wheels) side before the lid so leftovers land in the lid.
func packingSequence(_ container: Container) -> [Compartment] {
    let valid = container.compartments.filter { $0.dims.count == 3 }
    let rank: [String: Int]
    switch container.type {
    case .backpack: rank = ["laptop": 0, "front": 1]
    case .suitcase, .duffel: rank = ["base": 0, "main": 0, "lid": 1]
    }
    return valid.enumerated()
        .sorted { (rank[$0.element.name] ?? 2, $0.offset) < (rank[$1.element.name] ?? 2, $1.offset) }
        .map(\.element)
}

/// Where a `neededAtSecurity` item can be reached without unpacking: max y for a
/// top-loading backpack, max z (the lid side) for a clamshell suitcase or duffel.
func touchesOpening(_ p: Placement, container: Container) -> Bool {
    guard let size = compartment(named: p.compartment, in: container)?.size else { return false }
    switch container.type {
    case .backpack: return p.y + p.h >= size.h - eps
    case .suitcase, .duffel: return p.z + p.d >= size.d - eps
    }
}
