import Foundation

/// Extracts intentional vibrato (≈4–8 Hz hand oscillation) from the pitch stream.
/// A 2nd-order band-pass (RBJ biquad) isolates the band; an envelope follower +
/// gate decides whether the oscillation is strong enough to be "singing"
/// rather than sensor noise or slow drift.
public struct VibratoEngine {
    public let sampleRate: Double
    public let centerHz: Double
    public let q: Double
    public let gateThreshold: Double

    // Biquad band-pass state (RBJ cookbook, constant skirt gain BPF)
    private var b0 = 0.0, b1 = 0.0, b2 = 0.0, a1 = 0.0, a2 = 0.0
    private var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0
    private var envelope: Double = 0

    public private(set) var lastActive = false

    public init(sampleRate: Double = 60, centerHz: Double = 5.5, q: Double = 2.5, gate: Double = 0.02) {
        self.sampleRate = sampleRate
        self.centerHz = centerHz
        self.q = q
        self.gateThreshold = gate
        recompute()
    }

    private mutating func recompute() {
        let w0 = 2 * Double.pi * centerHz / sampleRate
        let alpha = sin(w0) / (2 * q)
        let a0 = 1 + alpha
        b0 = alpha / a0
        b1 = 0
        b2 = -alpha / a0
        a1 = -2 * cos(w0) / a0
        a2 = (1 - alpha) / a0
    }

    /// Returns modulation depth in cents (signed, ±) and whether vibrato is active.
    public mutating func process(_ pitchSemitones: Double, dt: Double) -> (depthCents: Double, active: Bool) {
        let x = pitchSemitones
        let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2 = x1; x1 = x; y2 = y1; y1 = y
        // Envelope follower: fast attack, slow release.
        let rect = abs(y)
        let coef = rect > envelope ? 0.3 : 0.02
        envelope += coef * (rect - envelope)
        lastActive = envelope > gateThreshold
        // y is the band-passed deviation in semitones → cents.
        let depthCents = y * 100
        return (lastActive ? depthCents : 0, lastActive)
    }
}