import Foundation

public enum HandSide: String, Codable {
    case left, right
}

public struct LandmarkPoint: Equatable {
    public var x: Double          // normalized 0…1, image space (mirrored for selfie view upstream)
    public var y: Double          // normalized 0…1, top-down
    public var confidence: Double // 0…1

    public init(x: Double, y: Double, confidence: Double = 1.0) {
        self.x = x
        self.y = y
        self.confidence = confidence
    }
}

/// 21 landmarks in Vision index order:
/// 0 wrist; 1-4 thumb; 5-8 index; 9-12 middle; 13-16 ring; 17-20 little.
public struct HandFrame: Equatable {
    public var side: HandSide
    public var points: [LandmarkPoint]
    public var timestamp: Double  // seconds

    public init(side: HandSide, points: [LandmarkPoint], timestamp: Double) {
        self.side = side
        self.points = points
        self.timestamp = timestamp
    }

    public static let landmarkCount = 21
}

public enum Landmark {
    public static let wrist = 0
    public static let thumbTip = 4
    public static let indexTip = 8
    public static let indexMCP = 5
    public static let middleMCP = 9
    public static let middleTip = 12
}