import PackFitSchemas

public enum PlanViolation: Sendable, Equatable {
    case overlap(a: String, b: String)
    case outOfBounds(itemId: String)
    case floating(itemId: String, supportPct: Double)
    case fragileUnder(fragileId: String, aboveId: String)
    case heavyOnLight(heavyId: String, lightId: String)
    case uprightBroken(itemId: String)
    case securityNotOnTop(itemId: String)
    case wrongCompartment(itemId: String, compartment: String)
}

/// Every rule broken by `plan`, each reported once. Empty means the plan is physically
/// valid. Uses the same constraint functions as the solver. Pass the options the plan was
/// packed with if they differ from the defaults (support threshold, security rule).
public func validatePlan(
    _ plan: Plan, items: [Item], container: Container, options: PackOptions = .init()
) -> [PlanViolation] {
    var byId: [String: Item] = [:]
    for item in items where byId[item.id] == nil { byId[item.id] = item }

    var found: [PlanViolation] = []
    func add(_ v: PlanViolation?) {
        if let v, !found.contains(v) { found.append(v) }
    }
    for (i, c) in plan.placed.enumerated() {
        var others = plan.placed
        others.remove(at: i)
        add(compartmentViolation(c, placed: others, items: byId, container: container))
        add(boundsViolation(c, placed: others, items: byId, container: container))
        add(uprightViolation(c, placed: others, items: byId, container: container))
        add(overlapViolation(c, placed: others, items: byId, container: container))
        add(supportViolation(c, placed: others, items: byId, container: container, minPct: options.supportPct))
        add(fragileViolation(c, placed: others, items: byId, container: container))
        add(heavyOnLightViolation(c, placed: others, items: byId, container: container))
        if options.securityOnTop {
            add(securityViolation(c, placed: others, items: byId, container: container))
        }
    }
    return found
}
