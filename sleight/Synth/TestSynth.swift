import AVFoundation

/// Minimal mono saw synth for playing without Logic open. Not unit-tested;
/// verified by ear.
final class TestSynth {
    var isEnabled = true

    private let engine = AVAudioEngine()
    private var source: AVAudioSourceNode?
    private var phase: Double = 0
    private var baseFreq: Double = 261.63
    private var freq: Double = 261.63
    private var level: Float = 0
    private var targetLevel: Float = 0
    private var started = false
    private let sampleRate: Double = 44100

    init() {
        let sr = sampleRate
        source = AVAudioSourceNode { [weak self] _, _, frames, audioBufferList -> OSStatus in
            guard let self else { return noErr }
            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
            // click-free ~3ms level glide
            let glide = Float(1.0 - exp(-1.0 / (0.01 * self.sampleRate)))
            for frame in 0..<Int(frames) {
                self.level += (self.targetLevel - self.level) * glide
                self.phase += 2 * Double.pi * self.freq / self.sampleRate
                if self.phase > 2 * Double.pi { self.phase -= 2 * Double.pi }
                let saw = 2 * (self.phase / (2 * Double.pi)) - 1
                let soft = Float(saw * 0.7 + 0.3 * saw * abs(saw)) // gentle saturation
                let sample = soft * self.level
                for buf in abl {
                    let b = UnsafeMutableBufferPointer<Float>(buf)
                    if frame < b.count { b[frame] = sample }
                }
            }
            return noErr
        }
    }

    func start() {
        guard let source, !started else { return }
        engine.attach(source)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else { return }
        engine.connect(source, to: engine.mainMixerNode, format: format)
        try? engine.start()
        started = true
    }

    func handle(_ events: [MIDIEvent]) {
        guard isEnabled else { return }
        for e in events {
            switch e.kind {
            case let .noteOn(note, _):
                baseFreq = 440.0 * pow(2, (Double(note) - 69) / 12)
                freq = baseFreq
                targetLevel = 0.18
                start()
            case .noteOff:
                targetLevel = 0
            case let .cc(7, value):
                if targetLevel > 0 { targetLevel = Float(value) / 127 * 0.4 }
            case let .pitchBendSemitones(semis):
                freq = baseFreq * pow(2, semis / 12)
            default:
                break
            }
        }
    }

    func stopEngine() {
        engine.stop()
        started = false
    }
}