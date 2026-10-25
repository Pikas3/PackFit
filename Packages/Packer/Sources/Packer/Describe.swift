import PackFitSchemas

public enum VerticalPosition: String, Sendable, Equatable {
    case bottom, middle, top
}

/// One packing step as structured phrases for the voice coach. Phrase-ready, not prose.
public struct StepDescription: Sendable, Equatable {
    public var order: Int
    public var item: Item
    public var placement: Placement
    public var position: VerticalPosition      // .bottom | .middle | .top
    public var region: String                  // "back left corner", "front centre", ...
    public var near: [String]                  // names of touching already-placed items
    public var notes: [String]                 // "fragile, nothing goes on top", "keep accessible for security"
}

/// Describes step `order` of `plan`. Pass `container` for exact regions; without it the
/// compartment's extent is inferred from the plan.
public func describeStep(
    _ plan: Plan, items: [Item], order: Int, container: Container? = nil
) -> StepDescription? {
    guard let p = plan.placed.first(where: { $0.order == order }),
          let item = items.first(where: { $0.id == p.itemId }) else { return nil }
    let size = container.flatMap { compartment(named: p.compartment, in: $0)?.size }
        ?? inferredSize(plan.placed.filter { sameCompartment($0, p) })

    let names = Dictionary(items.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
    let near = plan.placed
        .filter { $0.order < order && sameCompartment($0, p) && touching($0, p) }
        .sorted { $0.order < $1.order }
        .compactMap { names[$0.itemId] }

    return StepDescription(order: order, item: item, placement: p,
                           position: verticalPosition(p, size: size),
                           region: region(p, size: size), near: near,
                           notes: notes(item, placement: p))
}

private func inferredSize(_ placed: [Placement]) -> Size {
    Size(w: placed.map { $0.x + $0.w }.max() ?? 1,
         h: placed.map { $0.y + $0.h }.max() ?? 1,
         d: placed.map { $0.z + $0.d }.max() ?? 1)
}

func verticalPosition(_ p: Placement, size: Size) -> VerticalPosition {
    if p.y <= eps { return .bottom }
    return p.y + p.h >= size.h * 2 / 3 - eps ? .top : .middle
}

/// Thirds of width (left / centre / right) and depth (back / middle / front), by the
/// item's centre. Items covering most of the floor are "across the whole bag".
func region(_ p: Placement, size: Size) -> String {
    if p.w >= size.w * 2 / 3 - eps && p.d >= size.d * 2 / 3 - eps { return "across the whole bag" }
    let third = { (centre: Double, length: Double) -> Int in
        centre < length / 3 - eps ? 0 : (centre > length * 2 / 3 + eps ? 2 : 1)
    }
    let col = p.w >= size.w * 2 / 3 - eps ? 1 : third(p.x + p.w / 2, size.w)
    let row = p.d >= size.d * 2 / 3 - eps ? 1 : third(p.z + p.d / 2, size.d)
    let side = ["left", "centre", "right"][col]
    switch (row, col) {
    case (1, 1): return "centre"
    case (1, _): return "\(side) side"
    case (0, 1): return "back centre"
    case (2, 1): return "front centre"
    default: return "\(row == 0 ? "back" : "front") \(side) corner"
    }
}

/// Faces in contact: touching on one axis, overlapping on the other two.
func touching(_ a: Placement, _ b: Placement) -> Bool {
    let ox = overlap(a.x, a.x + a.w, b.x, b.x + b.w)
    let oy = overlap(a.y, a.y + a.h, b.y, b.y + b.h)
    let oz = overlap(a.z, a.z + a.d, b.z, b.z + b.d)
    let contact = { (o: Double) in abs(o) <= eps }
    return (contact(ox) && oy > eps && oz > eps)
        || (contact(oy) && ox > eps && oz > eps)
        || (contact(oz) && ox > eps && oy > eps)
}

private func notes(_ item: Item, placement p: Placement) -> [String] {
    var out: [String] = []
    if let name = p.compartment, name != mainCompartment {
        switch name {
        case "base": out.append("goes in the base (wheels) side")
        case "lid": out.append("goes in the lid side")
        default: out.append("goes in the \(name) compartment")
        }
    }
    if item.fragile { out.append("fragile, only soft clothes on top") }
    if item.upright {
        let standing = abs(p.h - item.h) <= eps
        out.append(standing ? "keep upright" : "too tall to stand, close it tightly and lay it flat")
    }
    if item.soft && p.h < min(item.w, item.h, item.d) - eps { out.append("soft, press it down to fit") }
    if item.neededAtSecurity == true { out.append("keep accessible for security") }
    return out
}
