import Foundation
import Vision
import CoreVideo

public protocol HandTracker: AnyObject {
    /// Detect hands in a camera pixel buffer; returns one HandFrame per detected hand.
    func detect(_ pixelBuffer: CVPixelBuffer, at t: Double) -> [HandFrame]
}

public final class VisionHandTracker: HandTracker {
    private let request: VNDetectHumanHandPoseRequest

    /// Explicit Vision joint → our 0-20 index mapping (matches Types.swift order).
    private static let jointIndex: [VNHumanHandPoseObservation.JointName: Int] = [
        .wrist: 0,
        .thumbCMC: 1, .thumbMP: 2, .thumbIP: 3, .thumbTip: 4,
        .indexMCP: 5, .indexPIP: 6, .indexDIP: 7, .indexTip: 8,
        .middleMCP: 9, .middlePIP: 10, .middleDIP: 11, .middleTip: 12,
        .ringMCP: 13, .ringPIP: 14, .ringDIP: 15, .ringTip: 16,
        .littleMCP: 17, .littlePIP: 18, .littleDIP: 19, .littleTip: 20,
    ]

    public init(maxHands: Int = 2) {
        request = VNDetectHumanHandPoseRequest()
        request.maximumHandCount = maxHands
    }

    public func detect(_ pixelBuffer: CVPixelBuffer, at t: Double) -> [HandFrame] {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .leftMirrored)
        try? handler.perform([request])
        guard let observations = request.results else { return [] }
        return observations.compactMap { (obs: VNHumanHandPoseObservation) -> HandFrame? in
            guard let all = try? obs.recognizedPoints(.all) else { return nil }
            var pts: [Int: (x: Double, y: Double, c: Double)] = [:]
            for (joint, point) in all {
                if let idx = Self.jointIndex[joint] {
                    pts[idx] = (Double(point.location.x), Double(point.location.y), Double(point.confidence))
                }
            }
            guard pts[Landmark.wrist] != nil else { return nil }
            guard let wristX = pts[Landmark.wrist]?.x else { return nil }
            // No handedness in Vision hand pose — assign by image side (un-mirrored
            // Vision coords: person's right hand appears at x < 0.5). For the
            // theremin mapping this is exactly the zone assignment we want.
            let side: HandSide = wristX < 0.5 ? .right : .left
            return Self.makeFrame(side: side, points: pts, timestamp: t)
        }
    }

    /// Pure + fixture-testable: mirror X for selfie view, gate confidence,
    /// bridge weak/missing points to the previous good landmark.
    static func makeFrame(side: HandSide, points: [Int: (x: Double, y: Double, c: Double)], timestamp: Double) -> HandFrame {
        var out: [LandmarkPoint] = []
        out.reserveCapacity(HandFrame.landmarkCount)
        for i in 0..<HandFrame.landmarkCount {
            if let p = points[i], p.c >= 0.5 {
                out.append(LandmarkPoint(x: 1 - p.x, y: p.y, confidence: p.c))
            } else {
                let fallback = out.last ?? LandmarkPoint(x: 0.5, y: 0.5, confidence: 0)
                out.append(LandmarkPoint(x: fallback.x, y: fallback.y, confidence: 0))
            }
        }
        return HandFrame(side: side, points: out, timestamp: timestamp)
    }
}