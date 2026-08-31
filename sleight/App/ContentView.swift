import SwiftUI
import AVFoundation

struct ContentView: View {
    @StateObject private var controller = SleightController()
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            HUDView(model: controller.model)
            ZStack {
                CameraPreview(session: controller.captureSession)
                    .ignoresSafeArea(edges: .bottom)
                OverlayView(model: controller.model,
                            pitchBand: controller.pipeline.instrument.pitchBand,
                            volumeBand: controller.pipeline.instrument.volumeBand)
                    .ignoresSafeArea(edges: .bottom)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                TrackingCard(model: controller.model, controller: controller)
            }
            toolbar
        }
        .onAppear { controller.startSession() }
        .sheet(isPresented: $showSettings) {
            SettingsSheet(controller: controller)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 16) {
            Picker("Instrument", selection: Binding(
                get: { controller.settings.instrumentRaw },
                set: { controller.settings.instrumentRaw = $0; controller.applySettings() }
            )) {
                ForEach(InstrumentType.allCases) { t in
                    Text(t.rawValue).tag(t.rawValue)
                }
            }
            .frame(width: 150)

            Toggle("Practice (silent)", isOn: Binding(
                get: { controller.settings.practice },
                set: { newValue in
                    controller.settings.practice = newValue
                    controller.applySettings()
                }))

            Button(controller.model.overlay.trackingActive == false && controller.capture.isRunning ? "Restart" : "Camera: on") {
                controller.stopSession()
                controller.startSession()
            }
            .buttonStyle(.bordered)

            Spacer()

            Button("Settings…") { showSettings = true }
                .buttonStyle(.borderedProminent)
        }
        .padding(12)
        .background(.bar)
    }
}

/// "Raise a hand" card. Observes the model directly so it disappears the
/// moment tracking starts (ContentView itself doesn't subscribe to the model)
/// and the diagnostic line stays live at frame rate while it's visible.
private struct TrackingCard: View {
    @ObservedObject var model: PipelineModel
    let controller: SleightController

    var body: some View {
        if !model.overlay.trackingActive {
            VStack(spacing: 6) {
                Text("Raise a hand")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                Text("right hand = pitch · left hand = volume · pinch = note")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.7))
                Text(controller.diagnostic)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.55))
            }
            .padding(24)
            .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 14))
            .allowsHitTesting(false)
        }
    }
}

struct SettingsSheet: View {
    @ObservedObject var controller: SleightController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Sleight Settings").font(.title2.bold())

            GroupBox("Pitch zone (right hand)") {
                VStack(alignment: .leading) {
                    rangeSlider(label: "Horizontal band", lo: Binding(
                        get: { controller.settings.pitchLo },
                        set: { controller.settings.pitchLo = $0; controller.applySettings() }),
                        hi: Binding(
                            get: { controller.settings.pitchHi },
                            set: { controller.settings.pitchHi = $0; controller.applySettings() }))
                }
            }

            GroupBox("Volume zone (left hand)") {
                VStack(alignment: .leading) {
                    rangeSlider(label: "Vertical band", lo: Binding(
                        get: { controller.settings.volLo },
                        set: { controller.settings.volLo = $0; controller.applySettings() }),
                        hi: Binding(
                            get: { controller.settings.volHi },
                            set: { controller.settings.volHi = $0; controller.applySettings() }))
                }
            }

            GroupBox("Music") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Picker("Scale", selection: Binding(
                            get: { controller.settings.scaleRaw },
                            set: { controller.settings.scaleRaw = $0; controller.applySettings() })) {
                            ForEach(Scale.allCases) { s in
                                Text(s.rawValue).tag(s.rawValue)
                            }
                        }
                        Picker("Root", selection: Binding(
                            get: { controller.settings.root },
                            set: { controller.settings.root = $0; controller.applySettings() })) {
                            ForEach(48...72, id: \.self) { n in
                                Text(MusicTheory.noteName(n)).tag(n)
                            }
                        }
                        Picker("Octaves", selection: Binding(
                            get: { controller.settings.octaves },
                            set: { controller.settings.octaves = $0; controller.applySettings() })) {
                            ForEach([1.0, 1.5, 2.0, 3.0], id: \.self) { o in
                                Text("\(o, specifier: "%.1f")").tag(o)
                            }
                        }
                        Picker("Bend range", selection: Binding(
                            get: { controller.settings.bendRange },
                            set: { controller.settings.bendRange = $0; controller.applySettings() })) {
                            ForEach([1.0, 2.0, 4.0, 12.0], id: \.self) { r in
                                Text("±\(Int(r)) st").tag(r)
                            }
                        }
                    }
                    HStack {
                        Picker("MIDI protocol", selection: Binding(
                            get: { controller.settings.midiModeRaw },
                            set: { controller.settings.midiModeRaw = $0; controller.applySettings() })) {
                            Text("MIDI 2.0 (UMP)").tag(MIDIMode.ump.rawValue)
                            Text("MPE (MIDI 1.1)").tag(MIDIMode.mpe.rawValue)
                            Text("MIDI 1.1").tag(MIDIMode.legacy.rawValue)
                        }
                        Toggle("Glide", isOn: Binding(
                            get: { controller.settings.glide == .glide && controller.settings.midiMode != .legacy },
                            set: { controller.settings.glideRaw = $0 ? GlideMode.glide.rawValue : GlideMode.stepped.rawValue
                                controller.applySettings() }))
                            .disabled(controller.settings.midiMode == .legacy)
                    }
                }
            }

            GroupBox("Instrument") {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Instrument", selection: Binding(
                        get: { controller.settings.instrumentRaw },
                        set: { controller.settings.instrumentRaw = $0; controller.applySettings() }
                    )) {
                        ForEach(InstrumentType.allCases) { t in
                            Text(t.rawValue).tag(t.rawValue)
                        }
                    }
                    if controller.settings.instrumentType == .polyPads {
                        Stepper("Voices: \(controller.settings.voiceCount)", value: Binding(
                            get: { controller.settings.voiceCount },
                            set: { controller.settings.voiceCount = $0; controller.applySettings() }
                        ), in: 2...4)
                    }
                }
            }

            GroupBox("AR Pads") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Show AR pad targets (Poly Pads)", isOn: Binding(
                        get: { controller.settings.arPadsEnabled },
                        set: { controller.settings.arPadsEnabled = $0; controller.applySettings() }))
                    Stepper("Pads: \(controller.settings.padCount)", value: Binding(
                        get: { controller.settings.padCount },
                        set: { controller.settings.padCount = $0; controller.applySettings() }
                    ), in: 4...16)
                    HStack {
                        Text("BPM")
                        Slider(value: Binding(
                            get: { controller.settings.bpm },
                            set: { controller.settings.bpm = $0; controller.applySettings() }
                        ), in: 40...240, step: 1)
                        Text("\(Int(controller.settings.bpm.rounded()))")
                            .font(.system(size: 11, design: .monospaced))
                            .frame(width: 36)
                    }
                    Picker("Ignore shorter than", selection: Binding(
                        get: { controller.settings.minNoteSubdivisionRaw },
                        set: { controller.settings.minNoteSubdivisionRaw = $0; controller.applySettings() }
                    )) {
                        ForEach(NoteSubdivision.allCases) { s in
                            Text(s.displayName).tag(s.rawValue)
                        }
                    }
                    Text(String(format: "Ignore shorter than %.0f ms. Hover over a pad, then curl to press.",
                                controller.settings.minPressDuration * 1000))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            GroupBox("Audio") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Mute Sleight's synth output", isOn: Binding(
                        get: { controller.settings.muteSleight },
                        set: { controller.settings.muteSleight = $0; controller.applySettings() }))
                    Toggle("Auto-mute when a DAW host connects", isOn: Binding(
                        get: { controller.settings.autoMuteWhenHostConnected },
                        set: { controller.settings.autoMuteWhenHostConnected = $0; controller.applySettings() }))
                    Text("When a DAW host connects via the audio/MIDI plug-in, Sleight's built-in synth is silenced so the DAW's instrument is the only voice heard.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 460)
    }

    private func rangeSlider(label: String, lo: Binding<Double>, hi: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            HStack {
                Slider(value: lo, in: 0...0.9)
                Text(String(format: "%.2f", lo.wrappedValue))
                    .font(.system(size: 11, design: .monospaced)).frame(width: 36)
            }
            HStack {
                Slider(value: hi, in: 0...1)
                Text(String(format: "%.2f", hi.wrappedValue))
                    .font(.system(size: 11, design: .monospaced)).frame(width: 36)
            }
        }
    }
}