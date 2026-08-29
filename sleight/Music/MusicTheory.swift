import Foundation

public enum Scale: String, Codable, CaseIterable, Identifiable {
    case chromatic, major, minor, minorPentatonic, free

    public var id: String { rawValue }

    public var intervals: [Int] {
        switch self {
        case .chromatic: return Array(0...11)
        case .major: return [0, 2, 4, 5, 7, 9, 11]
        case .minor: return [0, 2, 3, 5, 7, 8, 10]
        case .minorPentatonic: return [0, 3, 5, 7, 10]
        case .free: return []
        }
    }
}

public enum MusicTheory {
    /// Snap continuous pitch (semitones) to nearest tone of scale rooted at `root`
    /// (root given as pitch class 0-11). `.free` returns input untouched;
    /// `.chromatic` rounds to nearest semitone.
    public static func quantize(_ pitch: Double, scale: Scale, root: Int = 0) -> Double {
        switch scale {
        case .free:
            return pitch
        case .chromatic:
            return pitch.rounded()
        default:
            break
        }

        let intervals = scale.intervals
        let floorOctave = Int(pitch.rounded(.down) / 12)   // octave containing the pitch
        var best = pitch
        var bestDist = Double.infinity
        for octave in (floorOctave - 1)...(floorOctave + 1) {
            for iv in intervals {
                let candidate = Double(root + iv + 12 * octave)
                let d = abs(candidate - pitch)
                if d < bestDist {
                    bestDist = d
                    best = candidate
                }
            }
        }
        return best
    }

    public static func noteName(_ semitone: Int) -> String {
        let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let pc = ((semitone % 12) + 12) % 12
        let octave = (semitone - pc) / 12 - 1
        return "\(names[pc])\(octave)"
    }
}