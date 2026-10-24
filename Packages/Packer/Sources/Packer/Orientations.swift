import PackFitSchemas

struct Orientation: Equatable {
    var w: Double, h: Double, d: Double
}

/// Orientations to try, flat-first (smallest height first, then widest), with soft items'
/// height compressed by `compressSoftPct`.
///
/// - `upright` items keep their scanned `h` vertical: (w, h, d) and (d, h, w).
/// - `options.orientations == 2` keeps only the flat orientation and its 90 degree turn.
func orientations(for item: Item, options: PackOptions) -> [Orientation] {
    let (w, h, d) = (item.w, item.h, item.d)
    var all: [Orientation]
    if item.upright {
        all = [Orientation(w: w, h: h, d: d), Orientation(w: d, h: h, d: w)]
    } else {
        all = [
            Orientation(w: w, h: h, d: d), Orientation(w: d, h: h, d: w),
            Orientation(w: w, h: d, d: h), Orientation(w: h, h: d, d: w),
            Orientation(w: h, h: w, d: d), Orientation(w: d, h: w, d: h),
        ]
        if options.orientations <= 2 {
            let minH = all.map(\.h).min()!
            all = all.filter { $0.h <= minH + eps }
        }
    }
    // Index as the last key keeps the order total.
    let ordered = all.enumerated().sorted { a, b in
        (a.element.h, -a.element.w, a.offset) < (b.element.h, -b.element.w, b.offset)
    }.map(\.element)

    var unique: [Orientation] = []
    for o in ordered where !unique.contains(where: { sameSize($0, o) }) {
        unique.append(o)
    }
    if item.soft {
        let factor = 1 - min(max(options.compressSoftPct, 0), 100) / 100
        unique = unique.map { Orientation(w: $0.w, h: max($0.h * factor, eps * 10), d: $0.d) }
    }
    let pad = footprintPad(item, options: options)
    if pad > eps {
        unique = unique.map { Orientation(w: $0.w + pad, h: $0.h, d: $0.d + pad) }
    }
    return unique
}

/// Room added to width and depth for a measured size that may be a little off. Height is
/// never padded, so stacked items still rest exactly on each other.
func footprintPad(_ item: Item, options: PackOptions) -> Double {
    guard options.uncertaintyGapCm > eps, !item.soft, let m = item.measurement else { return 0 }
    switch m.method {
    case .manual, .catalog: return 0
    case .lidar, .ar, .reference, .estimate:
        let k = min(max((1 - m.confidence) / 0.5, 0), 1)
        return options.uncertaintyGapCm * k
    }
}

private func sameSize(_ a: Orientation, _ b: Orientation) -> Bool {
    abs(a.w - b.w) <= eps && abs(a.h - b.h) <= eps && abs(a.d - b.d) <= eps
}
