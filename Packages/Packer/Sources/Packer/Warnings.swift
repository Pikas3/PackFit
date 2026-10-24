import PackFitSchemas

/// Things the traveller should know about a plan. The packer never refuses a plan over
/// them: the bag may still close, and the scale at the airport is the authority.
public enum PlanWarning: Sendable, Equatable {
    /// The packed items weigh more than the bag's limit.
    case overWeight(kg: Double, limitKg: Double)
    /// Within 10% of the limit, before souvenirs and a toothbrush.
    case nearWeightLimit(kg: Double, limitKg: Double)
    /// Items that did not fit.
    case unplaced(count: Int)
}

/// Warnings for `plan` in `container`, most serious first. `bagKg` is the empty bag's own
/// weight when known; airlines weigh it too.
public func planWarnings(_ plan: Plan, container: Container, bagKg: Double = 0) -> [PlanWarning] {
    var out: [PlanWarning] = []
    let kg = plan.stats.kg + max(bagKg, 0)
    let limit = container.weightLimitKg
    if limit > eps {
        if kg > limit + eps {
            out.append(.overWeight(kg: kg, limitKg: limit))
        } else if kg >= 0.9 * limit - eps {
            out.append(.nearWeightLimit(kg: kg, limitKg: limit))
        }
    }
    if !plan.unplaced.isEmpty { out.append(.unplaced(count: plan.unplaced.count)) }
    return out
}
