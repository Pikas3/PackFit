import PackFitSchemas

/// Why an item ended up in `Plan.unplaced`, most specific first.
public enum UnplacedReason: Sendable, Equatable {
    /// Duplicate id or a zero dimension.
    case invalid
    /// No orientation fits any compartment that takes it, even an empty one.
    case tooLarge
    /// It would fit if it could go above a fragile item.
    case fragileInTheWay
    /// It fits the empty bag, but the space is used by the items placed before it.
    case noRoom
}

/// A reason for every id in `plan.unplaced`. Pass the options the plan was packed with.
public func explainUnplaced(
    _ plan: Plan, items: [Item], container: Container, options: PackOptions = .init()
) -> [String: UnplacedReason] {
    var byId: [String: Item] = [:]
    for item in items where byId[item.id] == nil { byId[item.id] = item }
    let placedIds = Set(plan.placed.map(\.itemId))

    var out: [String: UnplacedReason] = [:]
    for id in plan.unplaced where out[id] == nil {
        guard let item = byId[id], !placedIds.contains(id),
              item.w > eps, item.h > eps, item.d > eps else {
            out[id] = .invalid
            continue
        }
        let compartments = packingSequence(container).filter { accepts($0, item: item, container: container) }
        let fitsEmpty = compartments.contains { comp in
            orientations(for: item, options: options, space: comp.size).contains {
                $0.w <= comp.size.w + eps && $0.h <= comp.size.h + eps && $0.d <= comp.size.d + eps
            }
        }
        guard fitsEmpty else {
            out[id] = .tooLarge
            continue
        }
        let fitsOverFragile = compartments.contains { comp in
            let inside = plan.placed.filter { compartmentName($0) == comp.name }
            return placeOne(item, placed: inside, compartment: comp, container: container,
                            items: byId, options: options, flatFirst: true, skipFragile: true) != nil
        }
        out[id] = fitsOverFragile ? .fragileInTheWay : .noRoom
    }
    return out
}
