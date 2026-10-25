import PackFitSchemas

// One pure function per rule. `placed` is every other placement to check against; each
// function filters to the candidate's compartment itself. Pairwise rules check both
// directions, so the solver (placed = earlier steps) and validatePlan (placed = everything
// else) share them.

/// Every rule, cheapest first. The solver accepts a candidate only when this is nil.
func firstViolation(
    _ c: Placement, placed: [Placement], items: [String: Item], container: Container,
    options: PackOptions, skipFragile: Bool = false
) -> PlanViolation? {
    compartmentViolation(c, placed: placed, items: items, container: container)
        ?? boundsViolation(c, placed: placed, items: items, container: container)
        ?? uprightViolation(c, placed: placed, items: items, container: container)
        ?? overlapViolation(c, placed: placed, items: items, container: container)
        ?? supportViolation(c, placed: placed, items: items, container: container, minPct: options.supportPct)
        ?? (skipFragile ? nil : fragileViolation(c, placed: placed, items: items, container: container))
        ?? heavyOnLightViolation(c, placed: placed, items: items, container: container)
        ?? (options.securityOnTop
            ? securityViolation(c, placed: placed, items: items, container: container) : nil)
}

func overlapViolation(_ c: Placement, placed: [Placement], items: [String: Item], container: Container) -> PlanViolation? {
    for p in placed where sameCompartment(c, p) && boxesOverlap(c, p) {
        return .overlap(a: min(c.itemId, p.itemId), b: max(c.itemId, p.itemId))
    }
    return nil
}

func boundsViolation(_ c: Placement, placed: [Placement], items: [String: Item], container: Container) -> PlanViolation? {
    guard let size = compartment(named: c.compartment, in: container)?.size else {
        return .wrongCompartment(itemId: c.itemId, compartment: compartmentName(c))
    }
    let inside = c.x >= -eps && c.y >= -eps && c.z >= -eps
        && c.x + c.w <= size.w + eps && c.y + c.h <= size.h + eps && c.z + c.d <= size.d + eps
        && c.w > eps && c.h > eps && c.d > eps
    return inside ? nil : .outOfBounds(itemId: c.itemId)
}

/// Rule 2: at least `minPct` of the footprint rests on the floor or on tops of other items.
func supportViolation(
    _ c: Placement, placed: [Placement], items: [String: Item], container: Container, minPct: Double = 60
) -> PlanViolation? {
    if c.y <= eps { return nil }
    var area = 0.0
    for p in placed where sameCompartment(c, p) && restsOn(c, p) {
        area += footprintOverlapArea(c, p)
    }
    let pct = 100 * area / (c.w * c.d)
    return pct >= minPct - eps ? nil : .floating(itemId: c.itemId, supportPct: pct)
}

/// Soft items up to this weight may go above a fragile one, like clothes over a laptop.
let cushionMaxKg = 1.0

/// A light soft item that protects rather than crushes.
func cushions(_ item: Item?) -> Bool {
    guard let item else { return false }
    return item.soft && !item.fragile && item.kg <= cushionMaxKg + eps
}

/// Rule 3: nothing above a fragile item's footprint except light soft items. Anything rigid
/// or heavy is rejected however high it sits, so it cannot rest on the cushioning either.
func fragileViolation(_ c: Placement, placed: [Placement], items: [String: Item], container: Container) -> PlanViolation? {
    for p in placed where sameCompartment(c, p) {
        if items[p.itemId]?.fragile == true, isAbove(c, p), !cushions(items[c.itemId]) {
            return .fragileUnder(fragileId: p.itemId, aboveId: c.itemId)
        }
        if items[c.itemId]?.fragile == true, isAbove(p, c), !cushions(items[p.itemId]) {
            return .fragileUnder(fragileId: c.itemId, aboveId: p.itemId)
        }
    }
    return nil
}

/// Rule 4: an item may not rest on a softer item that is lighter than it.
func heavyOnLightViolation(_ c: Placement, placed: [Placement], items: [String: Item], container: Container) -> PlanViolation? {
    for p in placed where sameCompartment(c, p) {
        if restsOn(c, p), crushes(items[c.itemId], items[p.itemId]) {
            return .heavyOnLight(heavyId: c.itemId, lightId: p.itemId)
        }
        if restsOn(p, c), crushes(items[p.itemId], items[c.itemId]) {
            return .heavyOnLight(heavyId: p.itemId, lightId: c.itemId)
        }
    }
    return nil
}

private func crushes(_ upper: Item?, _ lower: Item?) -> Bool {
    guard let upper, let lower else { return false }
    return lower.hardness < upper.hardness - eps && upper.kg > lower.kg + eps
}

/// Rule 6: an upright item's horizontal footprint is its scanned w x d (so h is vertical),
/// unless it cannot stand in its compartment at all; then it may lie down.
func uprightViolation(_ c: Placement, placed: [Placement], items: [String: Item], container: Container) -> PlanViolation? {
    guard let item = items[c.itemId], item.upright else { return nil }
    if let size = compartment(named: c.compartment, in: container)?.size, !canStand(item, in: size) {
        return nil
    }
    let same = { (a: Double, b: Double) in abs(a - b) <= eps }
    let ok = (same(c.w, item.w) && same(c.d, item.d)) || (same(c.w, item.d) && same(c.d, item.w))
    return ok ? nil : .uprightBroken(itemId: c.itemId)
}

/// Rule 8: a `neededAtSecurity` item has nothing above it, or touches the opening.
func securityViolation(_ c: Placement, placed: [Placement], items: [String: Item], container: Container) -> PlanViolation? {
    for p in placed where sameCompartment(c, p) {
        if items[p.itemId]?.neededAtSecurity == true, isAbove(c, p), !touchesOpening(p, container: container) {
            return .securityNotOnTop(itemId: p.itemId)
        }
        if items[c.itemId]?.neededAtSecurity == true, isAbove(p, c), !touchesOpening(c, container: container) {
            return .securityNotOnTop(itemId: c.itemId)
        }
    }
    return nil
}

/// Rule 9: the item is allowed in its compartment, and the compartment exists.
func compartmentViolation(_ c: Placement, placed: [Placement], items: [String: Item], container: Container) -> PlanViolation? {
    guard let comp = compartment(named: c.compartment, in: container) else {
        return .wrongCompartment(itemId: c.itemId, compartment: compartmentName(c))
    }
    guard let item = items[c.itemId] else { return nil }
    return accepts(comp, item: item, container: container)
        ? nil : .wrongCompartment(itemId: c.itemId, compartment: comp.name)
}

// MARK: Geometry

func boxesOverlap(_ a: Placement, _ b: Placement) -> Bool {
    overlap(a.x, a.x + a.w, b.x, b.x + b.w) > eps
        && overlap(a.y, a.y + a.h, b.y, b.y + b.h) > eps
        && overlap(a.z, a.z + a.d, b.z, b.z + b.d) > eps
}

func footprintsOverlap(_ a: Placement, _ b: Placement) -> Bool {
    overlap(a.x, a.x + a.w, b.x, b.x + b.w) > eps && overlap(a.z, a.z + a.d, b.z, b.z + b.d) > eps
}

func footprintOverlapArea(_ a: Placement, _ b: Placement) -> Double {
    guard footprintsOverlap(a, b) else { return 0 }
    return overlap(a.x, a.x + a.w, b.x, b.x + b.w) * overlap(a.z, a.z + a.d, b.z, b.z + b.d)
}

/// `upper` is somewhere above `lower` with overlapping footprints.
func isAbove(_ upper: Placement, _ lower: Placement) -> Bool {
    footprintsOverlap(upper, lower) && upper.y >= lower.y + lower.h - eps
}

/// `upper` sits directly on `lower`'s top face.
func restsOn(_ upper: Placement, _ lower: Placement) -> Bool {
    footprintsOverlap(upper, lower) && abs(upper.y - (lower.y + lower.h)) <= eps
}
