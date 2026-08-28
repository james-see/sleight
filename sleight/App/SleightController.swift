import SwiftUI
import AVFoundation

/// Owns capture + pipeline + synth; pushes settings changes into the engine.
@MainActor
final class SleightController: ObservableObject {
    let model = PipelineModel()
    let settings = AppSettings()
    private(set) var capture = CaptureService()
    private(set) var pipeline: Pipeline!
    private let synth = TestSynth()
    private var started = false

    init() {
        pipeline = Pipeline(model: model)
        capture.onFrame = { [weak self] pb in
            self?.pipeline.process(pixelBuffer: pb)
        }
        applySettings()
        // Route instrument events to the test synth via a lightweight tap:
        // Pipeline sends MIDI itself; the synth listens to the same events by
        // observing the published overlay (note state) is too coarse, so we
        // bridge through a small hook on Pipeline instead.
        pipeline.onEvents = { [weak self] events in
            self?.synth.handle(events)
        }
    }

    func applySettings() {
        let inst = pipeline.instrument
        inst.pitchBand = settings.pitchLo...max(settings.pitchLo + 0.05, settings.pitchHi)
        inst.volumeBand = settings.volLo...max(settings.volLo + 0.05, settings.volHi)
        inst.scale = settings.scale
        inst.root = settings.root
        inst.octaves = settings.octaves
        inst.bendRangeSemitones = settings.bendRange
        pipeline.practiceMode = settings.practice
        synth.isEnabled = !settings.practice
    }

    func startSession() {
        guard !started else { return }
        started = true
        try? capture.start()
    }

    func stopSession() {
        capture.stop()
        started = false
    }

    var captureSession: AVCaptureSession { capture.captureSession }

    /// One-line pipeline health readout shown in the "Raise a hand" card.
    var diagnostic: String {
        let p = DebugProbe.shared
        let perm: String
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: perm = "ok"
        case .notDetermined: perm = "notDetermined"
        case .denied: perm = "DENIED"
        case .restricted: perm = "RESTRICTED"
        @unknown default: perm = "?"
        }
        return "cam: \(p.device) | \(p.frame) | frames: \(p.frames) | vision: \(p.obs) obs → \(p.hands) hands | err: \(p.err) | perm: \(perm)"
    }
}