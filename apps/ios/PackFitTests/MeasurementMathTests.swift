import Testing
@testable import PackFit

struct MeasurementMathTests {
    @Test func heightUses98thPercentile() {
        var samples = Array(repeating: 0.05, count: 98)
        samples.append(contentsOf: [0.10, 0.12])
        let result = MeasurementMath.heightMeters(samplesAbovePlane: samples)
        #expect(result.sampleCount == 100)
        #expect(result.heightM >= 0.05)
    }

    @Test func dimsConvertToCm() {
        let dims = MeasurementMath.dimsCm(widthM: 0.302, heightM: 0.018, depthM: 0.214)
        #expect(dims.w == 30.2)
        #expect(dims.h == 1.8)
        #expect(dims.d == 21.4)
    }
}
