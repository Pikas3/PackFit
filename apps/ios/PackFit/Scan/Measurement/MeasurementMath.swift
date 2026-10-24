import Foundation
import simd

/// Pure measurement helpers from depth samples → (w, h, d, confidence).
/// Units: metres in, centimetres out (for Item fields).
/// A measured size ready for `/scan/item`. cm.
struct MeasuredBox: Equatable, Sendable {
    var w: Double
    var h: Double
    var d: Double
    var confidence: Double
    var method: MeasureMethod
}

enum MeasurementMath {
    /// Height above plane from samples (metres). Uses 98th percentile.
    static func heightMeters(samplesAbovePlane: [Double]) -> (heightM: Double, sampleCount: Int) {
        let positive = samplesAbovePlane.filter { $0 > 0.002 }.sorted()
        guard !positive.isEmpty else { return (0.01, 0) }
        let index = min(positive.count - 1, Int(Double(positive.count - 1) * 0.98))
        return (positive[index], positive.count)
    }

    /// Confidence for a depth-fitted box. Starts at 0.95, floors at 0.5.
    static func fitConfidence(
        highConfidenceFraction: Double,
        minSideCm: Double,
        cellCount: Int,
        fillRatio: Double,
        longSideCm: Double,
        maxLongSideCm: Double = 100
    ) -> Double {
        var c = 0.95
        if highConfidenceFraction < 0.6 { c -= 0.1 }
        if minSideCm < 4 { c -= 0.1 }
        if cellCount < 30 { c -= 0.15 }
        if fillRatio < 0.6 { c -= 0.1 }
        if longSideCm > maxLongSideCm { c -= 0.2 }
        return max(0.5, c)
    }

    static func dimsCm(widthM: Double, heightM: Double, depthM: Double) -> (w: Double, h: Double, d: Double) {
        (round1(widthM * 100), round1(heightM * 100), round1(depthM * 100))
    }

    private static func round1(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }
}
