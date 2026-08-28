import SwiftUI

/// AppStorage-backed settings. UI binds here; SleightController pushes values
/// into the instrument/pipeline.
final class AppSettings: ObservableObject {
    @AppStorage("scale") var scaleRaw: String = Scale.minorPentatonic.rawValue
    @AppStorage("root") var root: Int = 60
    @AppStorage("octaves") var octaves: Double = 2
    @AppStorage("bendRange") var bendRange: Double = 2
    @AppStorage("pitchLo") var pitchLo: Double = 0.55
    @AppStorage("pitchHi") var pitchHi: Double = 0.95
    @AppStorage("volLo") var volLo: Double = 0.1
    @AppStorage("volHi") var volHi: Double = 0.7
    @AppStorage("practice") var practice: Bool = false

    var scale: Scale { Scale(rawValue: scaleRaw) ?? .minorPentatonic }
}