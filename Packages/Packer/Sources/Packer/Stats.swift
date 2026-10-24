import PackFitSchemas

/// fillPct over the compartments that hold at least one item; kg over placed items;
/// comHeightPct is the kg-weighted mean of each item's centre height as a % of its
/// compartment's height.
func computeStats(_ placed: [Placement], items: [String: Item], container: Container) -> PlanStats {
    var itemVolume = 0.0
    var usedVolume = 0.0
    var usedNames: Set<String> = []
    var kg = 0.0
    var kgHeight = 0.0
    for p in placed {
        guard let size = compartment(named: p.compartment, in: container)?.size else { continue }
        itemVolume += p.w * p.h * p.d
        if usedNames.insert(compartmentName(p)).inserted {
            usedVolume += size.w * size.h * size.d
        }
        let m = items[p.itemId]?.kg ?? 0
        kg += m
        kgHeight += m * (p.y + p.h / 2) / size.h
    }
    let fill = usedVolume > eps ? min(100, 100 * itemVolume / usedVolume) : 0
    let com = kg > eps ? min(100, 100 * kgHeight / kg) : 0
    return PlanStats(fillPct: fill, kg: kg, comHeightPct: com)
}
