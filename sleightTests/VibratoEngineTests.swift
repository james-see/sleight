import XCTest
@testable import sleight

final class VibratoEngineTests: XCTestCase {
    func testSingingVibratoPasses() {
        var e = VibratoEngine()
        var maxAbsDepth = 0.0
        var lastActive = false
        for i in 0..<300 { // 5s
            let t = Double(i) / 60.0
            let wiggle = 0.45 * sin(2 * Double.pi * 6.0 * t)   // 6 Hz, ±0.45 semitone (~45 cents)
            let r = e.process(60.0 + wiggle, dt: 1.0/60)
            if i >= 240 { maxAbsDepth = max(maxAbsDepth, abs(r.depthCents)) } // final second
            lastActive = r.active
        }
        XCTAssertGreaterThan(maxAbsDepth, 35)  // ~±41 cents detected after passband gain
        XCTAssertTrue(lastActive)
    }

    func testSlowDriftRejected() {
        var e = VibratoEngine()
        var lastDepth = 0.0
        for i in 0..<300 {
            let t = Double(i) / 60.0
            let drift = 1.2 * sin(2 * Double.pi * 0.8 * t)   // 0.8 Hz wander
            let r = e.process(60.0 + drift, dt: 1.0/60)
            lastDepth = r.depthCents
        }
        XCTAssertLessThan(lastDepth, 10)
    }

    func testFastTremorRejected() {
        var e = VibratoEngine()
        var lastDepth = 0.0
        for i in 0..<300 {
            let t = Double(i) / 60.0
            let tremor = 0.3 * sin(2 * Double.pi * 14.0 * t)  // 14 Hz noise
            let r = e.process(60.0 + tremor, dt: 1.0/60)
            lastDepth = r.depthCents
        }
        XCTAssertLessThan(lastDepth, 15)
    }
}