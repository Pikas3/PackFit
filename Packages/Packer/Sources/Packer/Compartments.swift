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

/// Hot in the solver's inner loop: the common case (both nil, a suitcase's main) skips
/// building names.
@inline(__always) func sameCompartment(_ a: Placement, _ b: Placement) -> Bool {
    a.compartment == b.compartment || compartmentName(a) == compartmentName(b)
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
func packingSequence(_ container: Container) -> [Compartment] {
    let valid = container.compartments.filter { $0.dims.count == 3 }
    guard container.type == .backpack else { return valid }
    let rank = ["laptop": 0, "front": 1]
    return valid.enumerated()
        .sorted { (rank[$0.element.name] ?? 2, $0.offset) < (rank[$1.element.name] ?? 2, $1.offset) }
        .map(\.element)
}

/// Where a `neededAtSecurity` item can be reached without unpacking: the top, max y.
/// A backpack stands up and opens at the top; a suitcase or duffel is packed lying open on
/// its back, so the lid closes over max y too.
func touchesOpening(_ p: Placement, container: Container) -> Bool {
    guard let size = compartment(named: p.compartment, in: container)?.size else { return false }
    return p.y + p.h >= size.h - eps
}
