import Testing
import simd
@testable import PackFit

struct MeasurementMathTests {
    @Test func footprintProjectsOntoPlaneAxes() {
        let origin = SIMD3<Float>(0, 0, 0)
        let normal = SIMD3<Float>(0, 1, 0)
        let a = SIMD3<Float>(0, 0, 0)
        let b = SIMD3<Float>(0.30, 0, 0.20)
        let fp = MeasurementMath.footprint(cornerA: a, cornerB: b, planeOrigin: origin, planeNormal: normal)
        #expect(abs(fp.widthM - 0.30) < 0.001)
        #expect(abs(fp.depthM - 0.20) < 0.001)
    }

    @Test func heightUses98thPercentile() {
        var samples = Array(repeating: 0.05, count: 98)
        samples.append(contentsOf: [0.10, 0.12])
        let result = MeasurementMath.heightMeters(samplesAbovePlane: samples)
        #expect(result.sampleCount == 100)
        #expect(result.heightM >= 0.05)
    }

    @Test func confidenceFloorsAtHalf() {
        let c = MeasurementMath.confidence(
            meanDepthConfidenceBelowMedium: true,
            footprintMinSideCm: 2,
            heightSampleCount: 5
        )
        #expect(c == 0.5)
    }

    @Test func dimsConvertToCm() {
        let dims = MeasurementMath.dimsCm(widthM: 0.302, heightM: 0.018, depthM: 0.214)
        #expect(dims.w == 30.2)
        #expect(dims.h == 1.8)
        #expect(dims.d == 21.4)
    }
}
