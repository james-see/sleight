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
                OverlayView(overlay: controller.model.overlay,
                            pitchBand: controller.pipeline.instrument.pitchBand,
                            volumeBand: controller.pipeline.instrument.volumeBand)
                    .ignoresSafeArea(edges: .bottom)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                if !controller.model.overlay.trackingActive {
                    VStack(spacing: 6) {
                        Text("Raise a hand")
                            .font(.title2.bold())
                            .foregroundStyle(.white)
                        Text("right hand = pitch · left hand = volume · pinch = note")
                            .font(.callout)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .padding(24)
                    .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 14))
                    .allowsHitTesting(false)
                }
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
            Picker("Instrument", selection: .constant(0)) {
                Text(Theremin().displayName).tag(0)
            }
            .pickerStyle(.menu)
            .frame(width: 150)
            .disabled(true) // v1: theremin only

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