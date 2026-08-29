import SwiftUI
import Combine

/// UserDefaults-backed settings. UI binds here; SleightController pushes values
/// into the instrument/pipeline.
///
/// `@AppStorage` was rejected: inside an ObservableObject its wrapper never
/// fires objectWillChange (that behavior exists only in a SwiftUI View), so
/// views observing this class never re-rendered — the practice toggle appeared
/// dead. Manual `@Published` + UserDefaults keeps the same API for call sites
/// while making the class a real publisher.
final class AppSettings: ObservableObject {
    @Published var scaleRaw: String
    @Published var root: Int
    @Published var octaves: Double
    @Published var bendRange: Double
    @Published var pitchLo: Double
    @Published var pitchHi: Double
    @Published var volLo: Double
    @Published var volHi: Double
    @Published var practice: Bool
    @Published var midiModeRaw: String
    @Published var glideRaw: String

    private var cancellables = Set<AnyCancellable>()

    private static let d = UserDefaults.standard

    init() {
        let d = Self.d
        scaleRaw = d.string(forKey: "scale") ?? Scale.minorPentatonic.rawValue
        root = d.object(forKey: "root") as? Int ?? 60
        octaves = d.object(forKey: "octaves") as? Double ?? 2
        bendRange = d.object(forKey: "bendRange") as? Double ?? 2
        pitchLo = d.object(forKey: "pitchLo") as? Double ?? 0.55
        pitchHi = d.object(forKey: "pitchHi") as? Double ?? 0.95
        volLo = d.object(forKey: "volLo") as? Double ?? 0.1
        volHi = d.object(forKey: "volHi") as? Double ?? 0.7
        practice = d.object(forKey: "practice") as? Bool ?? false
        midiModeRaw = d.string(forKey: "midiMode") ?? MIDIMode.ump.rawValue
        glideRaw = d.string(forKey: "glide") ?? GlideMode.glide.rawValue

        // Persist every change (fire-and-forget; UserDefaults writes are cheap).
        $scaleRaw.sink { d.set($0, forKey: "scale") }.store(in: &cancellables)
        $root.sink { d.set($0, forKey: "root") }.store(in: &cancellables)
        $octaves.sink { d.set($0, forKey: "octaves") }.store(in: &cancellables)
        $bendRange.sink { d.set($0, forKey: "bendRange") }.store(in: &cancellables)
        $pitchLo.sink { d.set($0, forKey: "pitchLo") }.store(in: &cancellables)
        $pitchHi.sink { d.set($0, forKey: "pitchHi") }.store(in: &cancellables)
        $volLo.sink { d.set($0, forKey: "volLo") }.store(in: &cancellables)
        $volHi.sink { d.set($0, forKey: "volHi") }.store(in: &cancellables)
        $practice.sink { d.set($0, forKey: "practice") }.store(in: &cancellables)
        $midiModeRaw.sink { d.set($0, forKey: "midiMode") }.store(in: &cancellables)
        $glideRaw.sink { d.set($0, forKey: "glide") }.store(in: &cancellables)
    }

    var scale: Scale { Scale(rawValue: scaleRaw) ?? .minorPentatonic }
    var midiMode: MIDIMode { MIDIMode(rawValue: midiModeRaw) ?? .ump }
    var glide: GlideMode { GlideMode(rawValue: glideRaw) ?? .glide }
}