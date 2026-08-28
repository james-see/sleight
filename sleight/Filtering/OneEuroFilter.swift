import Foundation

/// One-Euro filter (Casiez et al. 2012) — adaptive low-pass: heavy smoothing
/// when slow (kills jitter), opens up when fast (kills lag).
/// Standard form: https://gery.casiez.net/1euro/
public struct OneEuroFilter {
    public var minCutoff: Double   // Hz, baseline smoothing
    public var beta: Double        // speed coefficient
    public var dCutoff: Double     // Hz, derivative smoothing

    private var xPrev: Double?
    private var dxPrev: Double = 0

    public init(minCutoff: Double, beta: Double, dCutoff: Double) {
        self.minCutoff = minCutoff
        self.beta = beta
        self.dCutoff = dCutoff
    }

    private static func alpha(_ cutoff: Double, _ dt: Double) -> Double {
        let tau = 1.0 / (2.0 * Double.pi * cutoff)
        return 1.0 / (1.0 + tau / dt)
    }

    public mutating func filter(_ value: Double, dt: Double) -> Double {
        let dt = max(dt, 1e-4)
        let dx: Double
        if let xPrev { dx = (value - xPrev) / dt } else { dx = 0 }
        let aD = Self.alpha(dCutoff, dt)
        dxPrev = aD * dx + (1 - aD) * dxPrev
        let cutoff = minCutoff + beta * abs(dxPrev)
        let a = Self.alpha(cutoff, dt)
        let xHat: Double
        if let xPrev { xHat = a * value + (1 - a) * xPrev } else { xHat = value }
        xPrev = xHat
        return xHat
    }
}