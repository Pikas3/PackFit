import PackFitSchemas

struct Orientation: Equatable {
    var w: Double, h: Double, d: Double
}

/// Orientations to try, flat-first (smallest height first, then widest), with soft items'
/// height compressed by `compressSoftPct`.
///
/// - `upright` items keep their scanned `h` vertical: (w, h, d) and (d, h, w).
/// - `options.orientations == 2` keeps only the flat orientation and its 90 degree turn.
/// - With `space`, an upright item that cannot stand in it at all is treated as not upright
///   (a bottle taller than the bag lies down), matching `uprightViolation`.
func orientations(for item: Item, options: PackOptions, space: Size? = nil) -> [Orientation] {
    if item.upright, let space, !canStand(item, in: space) {
        var lying = item
        lying.upright = false
        return orientations(for: lying, options: options)
    }
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
    return unique
}

/// Whether `item` fits `space` standing with its scanned `h` vertical, ignoring everything
/// else in the bag.
func canStand(_ item: Item, in space: Size) -> Bool {
    let fitsH = item.h <= space.h + eps
    let a = item.w <= space.w + eps && item.d <= space.d + eps
    let b = item.d <= space.w + eps && item.w <= space.d + eps
    return fitsH && (a || b)
}

private func sameSize(_ a: Orientation, _ b: Orientation) -> Bool {
    abs(a.w - b.w) <= eps && abs(a.h - b.h) <= eps && abs(a.d - b.d) <= eps
}
