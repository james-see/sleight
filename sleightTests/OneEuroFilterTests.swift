import XCTest
@testable import sleight

final class OneEuroFilterTests: XCTestCase {
    /// Deterministic pseudo-noise (no randomness in tests).
    private func noise(_ i: Int) -> Double {
        let v = (i * 1103515245 + 12345) % 2000
        return Double(v) / 2000.0 - 0.5
    }

    func testReducesJitterOnStaticSignal() {
        var f = OneEuroFilter(minCutoff: 1.0, beta: 0.007, dCutoff: 1.0)
        var last: Double = 0
        for i in 0..<200 { last = f.filter(0.5 + noise(i), dt: 1.0/60) }
        let raw = (0..<200).map { abs(noise($0)) }.max() ?? 0
        XCTAssertLessThan(abs(last - 0.5), 0.05)
        XCTAssertLessThan(abs(last - 0.5), raw)
    }

    func testTracksSlowRampWithBoundedLag() {
        var f = OneEuroFilter(minCutoff: 1.0, beta: 0.007, dCutoff: 1.0)
        var out = 0.0
        for i in 0..<600 {
            let x = Double(i) / 600.0 * 0.5   // slow ramp to 0.5 over 10s
            out = f.filter(x, dt: 1.0/60)
        }
        XCTAssertEqual(out, 0.5, accuracy: 0.05)
    }

    func testFastStepFollowsWithSpeed() {
        var f = OneEuroFilter(minCutoff: 1.0, beta: 0.02, dCutoff: 1.0)
        for i in 0..<60 { _ = f.filter(0.5, dt: 1.0/60) }
        var out = 0.0
        for i in 0..<15 { out = f.filter(1.0, dt: 1.0/60) } // fast flick
        XCTAssertGreaterThan(out, 0.7) // adaptive cutoff opens up on fast motion
    }
}