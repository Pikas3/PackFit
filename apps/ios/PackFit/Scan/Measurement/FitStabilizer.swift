import Foundation
import simd

/// A fit followed across snapshots.
struct FitTrack: Sendable, Identifiable, Equatable {
    let id: Int
    var fit: BoxFit
    /// Consecutive updates whose raw fit stayed within tolerance of the smoothed one.
    var stableCount: Int
    var misses: Int
}

/// Smooths fits over time and decides when each one has settled. Tracks are matched to new
/// fits greedily by centre distance, nearest pair first.
struct FitStabilizer: Sendable {
    var tolerance: Float
    var requiredStable = 6
    var alpha: Float = 0.4
    var matchRadius: Float = 0.05
    var maxMisses = 5

    private(set) var tracks: [FitTrack] = []
    private var nextID = 1
    private var suppressed: [SIMD2<Float>] = []

    init(tolerance: Float) {
        self.tolerance = tolerance
    }

    func isStable(_ track: FitTrack) -> Bool { track.stableCount >= requiredStable }

    var stableTracks: [FitTrack] { tracks.filter(isStable) }

    mutating func update(_ fits: [BoxFit]) {
        var pairs: [(dist: Float, track: Int, fit: Int)] = []
        for (ti, t) in tracks.enumerated() {
            for (fi, f) in fits.enumerated() {
                let d = distance(t.fit.rect.center, f.rect.center)
                if d < matchRadius { pairs.append((d, ti, fi)) }
            }
        }
        pairs.sort { $0.dist != $1.dist ? $0.dist < $1.dist : ($0.track, $0.fit) < ($1.track, $1.fit) }
        var usedTracks = Set<Int>(), usedFits = Set<Int>()
        for p in pairs where !usedTracks.contains(p.track) && !usedFits.contains(p.fit) {
            usedTracks.insert(p.track)
            usedFits.insert(p.fit)
            tracks[p.track] = blend(tracks[p.track], with: fits[p.fit])
        }
        for ti in tracks.indices where !usedTracks.contains(ti) { tracks[ti].misses += 1 }
        tracks.removeAll { $0.misses > maxMisses }
        for (fi, f) in fits.enumerated() where !usedFits.contains(fi) {
            if suppressed.contains(where: { distance($0, f.rect.center) < matchRadius }) { continue }
            tracks.append(FitTrack(id: nextID, fit: f, stableCount: 1, misses: 0))
            nextID += 1
        }
    }

    /// Drops a track and ignores new fits near it (a false positive the user removed).
    mutating func suppress(id: Int) {
        guard let i = tracks.firstIndex(where: { $0.id == id }) else { return }
        suppressed.append(tracks[i].fit.rect.center)
        tracks.remove(at: i)
    }

    mutating func reset() {
        tracks = []
        suppressed = []
    }

    private func blend(_ track: FitTrack, with raw: BoxFit) -> FitTrack {
        var t = track
        let old = track.fit
        let deviation = max(
            distance(old.rect.center, raw.rect.center),
            abs(old.rect.long - raw.rect.long),
            abs(old.rect.short - raw.rect.short),
            abs(old.height - raw.height)
        )
        t.stableCount = deviation <= tolerance ? track.stableCount + 1 : 0
        t.misses = 0

        func mix(_ a: Float, _ b: Float) -> Float { a + alpha * (b - a) }
        var dy = raw.rect.yaw - old.rect.yaw
        if dy >= .pi / 2 { dy -= .pi }
        if dy < -.pi / 2 { dy += .pi }
        t.fit = BoxFit(
            rect: OrientedRect(
                center: old.rect.center + alpha * (raw.rect.center - old.rect.center),
                yaw: OrientedRect.normalizedYaw(old.rect.yaw + alpha * dy),
                long: mix(old.rect.long, raw.rect.long),
                short: mix(old.rect.short, raw.rect.short)
            ),
            height: mix(old.height, raw.height),
            cellCount: raw.cellCount,
            fillRatio: mix(old.fillRatio, raw.fillRatio)
        )
        return t
    }
}
