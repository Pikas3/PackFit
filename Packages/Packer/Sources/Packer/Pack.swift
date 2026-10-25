import Foundation
import PackFitSchemas

public enum HeavyBias: Sendable, Equatable {
    /// Suitcases: top-quartile-by-weight items are packed first so they land low and,
    /// with `wheelsSide == .back`, near the back (low z).
    case wheels
    case none
}

public struct PackOptions: Sendable, Equatable {
    public var orientations: Int = 6           // 6, or 2 for flat and flat-rotated only
    public var compressSoftPct: Double = 20
    public var supportPct: Double = 60
    public var heavyBias: HeavyBias = .wheels  // .wheels | .none
    public var securityOnTop: Bool = true
    public init() {}
}

/// Tolerance for every float comparison in the package.
let eps = 1e-6

/// Packs `items` into `container`. Deterministic: the result depends only on the set of
/// items (not their order), the container and the options.
public func pack(_ items: [Item], into container: Container, options: PackOptions = .init()) -> Plan {
    var byId: [String: Item] = [:]
    var unplaced: [String] = []
    var remaining: [Item] = []
    for item in sortedForPacking(items) {
        if byId[item.id] != nil || !(item.w > eps && item.h > eps && item.d > eps) {
            unplaced.append(item.id)   // duplicate id or degenerate dims: never silently dropped
            continue
        }
        byId[item.id] = item
        remaining.append(item)
    }

    // A few deterministic strategies; keep the best plan. Ties go to the earlier strategy.
    // Strategies whose switches cannot change anything for these items are skipped, and the
    // first plan that places everything is kept.
    var best: Plan?
    var tried: [Strategy] = []
    for strategy in Strategy.all {
        let effective = strategy.effective(for: remaining, container: container, options: options)
        if tried.contains(effective) { continue }
        tried.append(effective)
        let plan = packOnce(remaining, container: container, items: byId, options: options,
                            strategy: effective, alreadyUnplaced: unplaced)
        if best == nil || isBetter(plan, than: best!) { best = plan }
        if best!.unplaced.count == unplaced.count { break }
    }
    return best!
}

/// The order items are tried in. Every key ends in kg and then `id`, so it is total.
enum Ordering: Equatable {
    /// Largest flat footprint first: builds even layers.
    case footprint
    /// Largest volume first: big awkward items before the gaps fill.
    case volume
    /// Longest side first: long items get the bag's length before it is used up.
    case longest
}

/// How one packing attempt orders items and scores positions.
struct Strategy: Equatable {
    var ordering: Ordering = .footprint
    /// true: try orientations flat-first and take the first that fits anywhere.
    /// false: take the position with the lowest top over all orientations.
    var flatFirst: Bool
    /// Fragile items go after everything except security items, so they end up on top.
    var fragileLate: Bool
    /// Rule 7 ordering: top-quartile-by-weight items first (suitcases, `.wheels` only).
    var heavyFirst: Bool
    /// Rule 8 ordering: security items last. The false variants are a fallback for bags
    /// where that leaves something unplaced; the security constraint still holds there.
    var securityLast: Bool

    /// Switches that make no difference for these items turned off, so equivalent
    /// strategies compare equal.
    func effective(for items: [Item], container: Container, options: PackOptions) -> Strategy {
        var s = self
        s.fragileLate = fragileLate && items.contains(where: \.fragile)
        s.heavyFirst = heavyFirst && options.heavyBias == .wheels && container.type == .suitcase
        s.securityLast = securityLast && options.securityOnTop
            && items.contains { $0.neededAtSecurity == true }
        return s
    }

    /// In preference order: on equal plans the earlier strategy wins, so the rule-following
    /// orderings are kept unless they place fewer items.
    /// The other orderings come last and only with the rule-following switches, which keeps
    /// the worst case (something never fits) to 20 attempts.
    static let all: [Strategy] = [true, false].flatMap { securityLast in
        [true, false].flatMap { heavyFirst in
            [true, false].flatMap { flatFirst in
                [false, true].map { fragileLate in
                    Strategy(flatFirst: flatFirst, fragileLate: fragileLate,
                             heavyFirst: heavyFirst, securityLast: securityLast)
                }
            }
        }
    } + [Ordering.volume, .longest].flatMap { ordering in
        [true, false].map { flatFirst in
            Strategy(ordering: ordering, flatFirst: flatFirst, fragileLate: false,
                     heavyFirst: true, securityLast: true)
        }
    }
}

/// Fewer unplaced, then more packed volume, then lower centre of mass.
func isBetter(_ a: Plan, than b: Plan) -> Bool {
    if a.unplaced.count != b.unplaced.count { return a.unplaced.count < b.unplaced.count }
    let va = a.placed.reduce(0) { $0 + $1.w * $1.h * $1.d }
    let vb = b.placed.reduce(0) { $0 + $1.w * $1.h * $1.d }
    if abs(va - vb) > eps { return va > vb }
    return a.stats.comHeightPct < b.stats.comHeightPct - eps
}

func packOnce(
    _ items: [Item], container: Container, items byId: [String: Item], options: PackOptions,
    strategy: Strategy, alreadyUnplaced: [String]
) -> Plan {
    var remaining = strategy.ordering == .footprint ? items : sortedForPacking(items, by: strategy.ordering)
    var placedByCompartment: [String: [Placement]] = [:]
    for compartment in packingSequence(container) {
        let eligible = remaining.filter { accepts(compartment, item: $0, container: container) }
        let placed = packCompartment(eligible, compartment: compartment, container: container,
                                     items: byId, options: options, strategy: strategy)
        let placedIds = Set(placed.map(\.itemId))
        remaining.removeAll { placedIds.contains($0.id) }
        placedByCompartment[compartment.name] = placed
    }

    // Steps run compartment by compartment in the container's own order.
    var placed: [Placement] = []
    for compartment in container.compartments {
        for var p in placedByCompartment[compartment.name] ?? [] {
            p.order = placed.count
            placed.append(p)
        }
    }
    return Plan(placed: placed, unplaced: alreadyUnplaced + remaining.map(\.id),
                stats: computeStats(placed, items: byId, container: container))
}

/// Largest first by `ordering` (flat footprint by default), then heaviest, then `id`: a
/// total order, so input order never matters.
func sortedForPacking(_ items: [Item], by ordering: Ordering = .footprint) -> [Item] {
    func key(_ i: Item) -> Double {
        switch ordering {
        case .footprint: return flatFootprint(i)
        case .volume: return i.w * i.h * i.d
        case .longest: return max(i.w, i.h, i.d)
        }
    }
    return items.sorted { a, b in
        let fa = key(a), fb = key(b)
        if fa != fb { return fa > fb }
        if a.kg != b.kg { return a.kg > b.kg }
        if a.id != b.id { return a.id < b.id }
        return (a.w, a.h, a.d) < (b.w, b.h, b.d)
    }
}

func flatFootprint(_ item: Item) -> Double {
    let dims = [item.w, item.h, item.d].sorted()
    return dims[1] * dims[2]
}

/// Packs one compartment. `items` arrive in `sortedForPacking` order. Returned placements
/// carry `order` local to the compartment.
func packCompartment(
    _ items: [Item], compartment: Compartment, container: Container,
    items byId: [String: Item], options: PackOptions, strategy: Strategy
) -> [Placement] {
    var regular = items
    var security: [Item] = []
    if options.securityOnTop && strategy.securityLast {
        regular = items.filter { $0.neededAtSecurity != true }
        security = items.filter { $0.neededAtSecurity == true }
    }
    if strategy.heavyFirst, options.heavyBias == .wheels, container.type == .suitcase {
        // Stable partition keeps the sorted order inside each group.
        let heavy = topQuartileByWeight(regular)
        regular = regular.filter { heavy.contains($0.id) } + regular.filter { !heavy.contains($0.id) }
    }
    if strategy.fragileLate {
        regular = regular.filter { !$0.fragile } + regular.filter(\.fragile)
    }

    var placed: [Placement] = []
    for item in regular + security {
        if var p = placeOne(item, placed: placed, compartment: compartment, container: container,
                            items: byId, options: options, flatFirst: strategy.flatFirst) {
            p.order = placed.count
            placed.append(p)
        }
    }
    return placed
}

/// Ids of the heaviest quarter of `items` (rounded up), ties broken by id.
func topQuartileByWeight(_ items: [Item]) -> Set<String> {
    let byWeight = items.sorted { ($0.kg, $1.id) > ($1.kg, $0.id) }
    return Set(byWeight.prefix((items.count + 3) / 4).map(\.id))
}

/// Best position for `item` that passes every constraint. Candidates within an
/// orientation are ranked lowest, then back-most, then left-most.
///
/// - flatFirst: orientations in flat-first order; the first one that fits anywhere wins.
/// - otherwise: across all orientations, the lowest top (y + h) wins; flat-first breaks ties.
func placeOne(
    _ item: Item, placed: [Placement], compartment: Compartment, container: Container,
    items: [String: Item], options: PackOptions, flatFirst: Bool, skipFragile: Bool = false
) -> Placement? {
    let size = compartment.size
    let name = compartment.name == mainCompartment ? nil : compartment.name
    // Security items in a clamshell go toward the lid, where they stay reachable and may
    // have things on top (rule 8).
    let frontFirst = options.securityOnTop && item.neededAtSecurity == true && container.type != .backpack
    var best: Placement?
    for o in orientations(for: item, options: options, space: size) {
        guard o.w <= size.w + eps, o.h <= size.h + eps, o.d <= size.d + eps else { continue }
        for point in candidatePoints(w: o.w, h: o.h, d: o.d, placed: placed, size: size,
                                     frontFirst: frontFirst) {
            if !flatFirst, let b = best, point.y + o.h >= b.y + b.h - eps { break }
            let candidate = Placement(itemId: item.id, x: point.x, y: point.y, z: point.z,
                                      w: o.w, h: o.h, d: o.d, order: placed.count, compartment: name)
            if firstViolation(candidate, placed: placed, items: items, container: container,
                              options: options, skipFragile: skipFragile) == nil {
                if flatFirst { return candidate }
                best = candidate
                break
            }
        }
    }
    return best
}
