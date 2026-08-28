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
        // macOS camera buffers are already upright — .leftMirrored (an iOS
        // front-camera orientation) made Vision analyze a rotated image and
        // detect nothing.
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)
        do {
            try handler.perform([request])
        } catch {
            DebugProbe.shared.noteDetection(obs: 0, hands: 0, err: "\(error)")
            return []
        }
        let observations = request.results ?? []
        let frames = observations.compactMap { (obs: VNHumanHandPoseObservation) -> HandFrame? in
            guard let all = try? obs.recognizedPoints(.all) else { return nil }
            var pts: [Int: (x: Double, y: Double, c: Double)] = [:]
            for (joint, point) in all {
                if let idx = Self.jointIndex[joint] {
                    pts[idx] = (Double(point.location.x), Double(point.location.y), Double(point.confidence))
                }
            }
            guard let wristX = pts[Landmark.wrist]?.x, let side = Self.assignSide(wristX: wristX) else { return nil }
            return Self.makeFrame(side: side, points: pts, timestamp: t)
        }
        DebugProbe.shared.noteDetection(obs: observations.count, hands: frames.count, err: "none")
        return frames
    }

    /// No handedness in Vision hand pose — assign by image side. Raw (.up)
    /// coords: the user's right hand appears on the frame's left (low x), and
    /// CameraPreview mirrors the video so the selfie view matches. A wrist in
    /// the center band is ambiguous — skip it rather than risk flipping the
    /// pitch/volume zones.
    static func assignSide(wristX: Double) -> HandSide? {
        if wristX < 0.4 { return .right }
        if wristX > 0.6 { return .left }
        return nil
    }

    /// Pure + fixture-testable: mirror X + flip Y for selfie top-down view
    /// (Vision normalized coords are bottom-left origin — raw y would draw the
    /// skeleton vertically flipped and invert the volume band), gate
    /// confidence, bridge weak/missing points to the previous good landmark.
    static func makeFrame(side: HandSide, points: [Int: (x: Double, y: Double, c: Double)], timestamp: Double) -> HandFrame {
        var out: [LandmarkPoint] = []
        out.reserveCapacity(HandFrame.landmarkCount)
        for i in 0..<HandFrame.landmarkCount {
            if let p = points[i], p.c >= 0.5 {
                out.append(LandmarkPoint(x: 1 - p.x, y: 1 - p.y, confidence: p.c))
            } else {
                let fallback = out.last ?? LandmarkPoint(x: 0.5, y: 0.5, confidence: 0)
                out.append(LandmarkPoint(x: fallback.x, y: fallback.y, confidence: 0))
            }
        }
        return HandFrame(side: side, points: out, timestamp: timestamp)
    }
}