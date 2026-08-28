# Sleight — Design Spec

**Date:** 2026-08-27
**Status:** Draft for review
**Owner:** James Campbell
**Domain:** sleightapp.xyz (purchased)

---

## 1. Overview

Sleight is a native macOS app that turns hand and finger movement — tracked from a normal webcam at 21 landmarks per hand via Apple Vision — into expressive MIDI. Your hands are the controller.

v1 ships one instrument (**Theremin**) plus the core engine: camera capture, hand tracking, low-latency filtering, a visual/AR feedback overlay on the live camera feed, and CoreMIDI output to Logic Pro (or any DAW). A small built-in test synth lets you hear yourself without opening Logic.

Future versions add more instruments (ribbon/strip, keyboard, bowed pads) built on the same tracking + mapping engine, an AUv3 plugin version, MPE/MIDI 2.0 output, and an optional ESP32 wireless-glove mode.

**Hero line (README):** *Sleight — sleight of hand for your DAW. A native macOS hand-tracking MIDI instrument. Your hands are the controller.*

---

## 2. Goals & Non-Goals

### Goals (v1)
- G1. Play a theremin with two hands: right hand controls pitch (horizontal), left hand controls volume (vertical), pinch gates notes.
- G2. Output MIDI 1.1 (pitch bend + CC + note on/off) to any CoreMIDI destination, with Logic Pro as the primary target.
- G3. Live camera view with an augmented overlay: tracked skeleton drawn on hands, pitch/volume guides, current note and level readouts. The visual feedback loop is a first-class feature, not a debug view.
- G4. Perceptually low latency: camera-to-MIDI under ~35ms median on an M4 Max at 60fps.
- G5. Small built-in test synth (AVAudioEngine) for Logic-free testing.
- G6. Pluggable instrument architecture so new instruments are additive, not rewrites.
- G7. Open-source on GitHub (james-see), README aimed at musicians, releases via tag-triggered CI (same pattern as ltx-video-mac).

### Non-Goals (v1)
- No AUv3 plugin (v2).
- No MPE / MIDI 2.0 (v2 — pitch bend ±2 semis + coarse/fine CC is enough for v1; see §8 for the resolution analysis).
- No audio synthesis beyond the test synth — Sleight is a controller, Logic does the synthesis.
- No keyboard instrument (a camera keyboard is a novelty, not a keybed replacement — comes later as a bonus mode).
- No ESP32/IMU hardware support (v3+ "glove mode").
- No Windows/Linux.

---

## 3. Platform & Stack

| Layer | Choice | Why |
|---|---|---|
| App | Swift, SwiftUI, macOS 14+ | Native, user's platform, Vision framework is first-party |
| Capture | AVFoundation (`AVCaptureSession` + `AVCaptureVideoDataOutput`) | 60fps, per-frame host-time timestamps |
| Tracking | Apple Vision `VNDetectHumanHandPoseRequest` | 21 landmarks × 2 hands, ANE-accelerated, no third-party model to ship |
| Filtering | One-Euro filter (Swift implementation, ~100 lines) | The AR/VR standard for low-latency adaptive smoothing |
| MIDI | CoreMIDI (`MIDISourceCreate` virtual destination) | Zero config in Logic; appears as a MIDI source |
| Test synth | AVAudioEngine + a simple oscillator/sampler | Self-contained, no dependencies |
| UI | SwiftUI + Metal (overlay rendering) | SwiftUI chrome; Metal view for camera + overlay compositing |
| Build/CI | Xcode project, tag-triggered GitHub Actions release (build/sign/notarize/DMG) | Proven pattern from ltx-video-mac |
| Tests | XCTest for engine/mapping/filter logic; manual QA checklist for latency | Pure-logic units are unit-testable; camera loop is not |

**Minimum hardware:** any Apple Silicon Mac (M1+). Built and tuned on M4 Max.

---

## 4. Architecture

Five stages, strict unidirectional flow, one thread boundary:

```
Camera (60fps) ──▶ [1] Capture ──▶ [2] Tracking ──▶ [3] Filtering ──▶ [4] Mapping ──▶ [5] Output
                    AVFoundation     Vision/ANE       One-Euro          Instrument        CoreMIDI
                    (capture queue)  (serial queue)   (serial queue)    plugin            (+ UI state)
```

- **Stages 1–4 run on a serial pipeline off the main thread.** Each stage is a struct with a `process(_:)` step; the pipeline drops frames if tracking falls behind (never queues — stale frames are useless for a real-time instrument).
- **Stage 5 fans out:** MIDI messages go to CoreMIDI; UI state (skeleton points, note, level) goes to the main thread via a `@MainActor` observable at display rate, decoupled from the 60fps pipeline.
- **Timestamps come from `CMSampleTimingInfo.hostTimeInNanoseconds`** on every frame — the camera frame's host-time anchor becomes the MIDI timestamp. No synthetic timestamps anywhere.

### 4.1 Capture
- `AVCaptureSession` preset `.high`, front camera (sitting at desk facing camera), 60fps where the camera supports it (falls back to 30fps).
- FaceTime HD on desktop Macs runs 30fps max; continuity camera / external cams may do 60. Design must feel good at 30fps; 60 is a bonus. Latency budget in §6 covers both.

### 4.2 Tracking
- `VNDetectHumanHandPoseRequest` per frame, maximumHandCount = 2.
- Landmarks normalized [0,1] × [0,1]; we keep wrist + all 4 points per finger + thumb tip & index tip as primary signals, full 21-point skeleton for overlay.
- Vision on Apple Silicon hands off to ANE; measured cost is a few ms/frame (verify in bench, §7).

### 4.3 Filtering
- One-Euro filter per landmark coordinate (x, y), per hand. Two parameter sets: position signals (pitch/volume) tuned for low jitter; velocity signals tuned for responsiveness.
- **Vibrato engine:** after filtering, the residual 4–8Hz band of the pitch signal is treated as *intentional* vibrato: hand oscillation at singing-vibrato rates passes through to a periodic pitch modulation, while sub-3Hz drift and >10Hz noise are suppressed. Implemented as a band-pass + magnitude gate on the pitch coordinate stream. This is a genuine differentiator — singer-style vibrato from bare hands.

### 4.4 Mapping (the pluggable instrument layer)

```swift
protocol Instrument {
    var id: String { get }
    var displayName: String { get }
    mutating func update(_ frame: HandFrame, at t: CMTime) -> [MIDIEvent]
    var calibration: CalibrationData { get set }
}
```

- `HandFrame` = filtered landmarks for both hands + timestamps + confidence.
- Instruments are value-type state machines: they consume frames, emit MIDI events, and own their own calibration. The app is a host: it runs capture/tracking/filtering, renders the overlay, routes events to MIDI + synth, and switches instruments.
- **v1 instrument — Theremin:**
  - Right hand X (in a user-defined horizontal band) → pitch: continuous, quantized to a selectable scale+root (chromatic / major / minor pentatonic / free), output as pitch bend from a held base note.
  - Left hand Y (in a user-defined vertical band) → volume (CC7 or CC11), with a proximity floor below which note-off fires.
  - Pinch (thumb-index distance < threshold, hysteresis 20%) → gate: note-on / note-off.
  - Hand roll (wrist→middle-finger angle) → CC1 modulation.
  - Vibrato engine modulates pitch bend depth (depth configurable, default ±30 cents).
- **Roadmap instruments (not in v1):** Ribbon (1D pitch strip + gate), Hold/Bow (sustained notes with pressure from hand height), Keyboard (grid novelty mode).

### 4.5 Output
- **CoreMIDI virtual source** named "Sleight." Logic sees it in the MIDI input list with zero configuration. MIDI 1.1 messages:
  - Note On/Off (base note, channel 1)
  - Pitch Bend (±2 semitone range as sent; Logic instruments handle the range)
  - CC7 volume, CC1 modulation
  - All-timestamped from the frame's host time.
- MIDI 2.0/MPE deferred to v2 (per-note pitch bend, ±48 semitones, high res — the right long-term fit for continuous pitch; Logic's exact MPE-record behavior with Alchemy to be verified at build time).

### 4.6 Visual feedback / AR overlay (first-class)
- Metal view composites, per frame: live camera image → 21-point hand skeletons with joint dots and bone lines → instrument-specific guides:
  - Theremin: two translucent vertical bands (pitch zone on the right, volume zone on the left) with a moving cursor line and the current note name + octave inside the pitch band.
  - Pinch indicator: ring around thumb-index that closes/fills as pinch approaches the threshold.
  - Level meter inside the volume band.
- Overlay state flows from the pipeline at display rate; rendering is decoupled from tracking (dropped UI frames never stall MIDI).
- A "practice" toggle freezes MIDI output while leaving visuals live (so you can set up your hand zones silently).

---

## 5. Data Flow (one frame)

1. Camera delivers `CMSampleBuffer` (host time T).
2. Vision extracts 21 landmarks × 2 hands (~3–8ms).
3. One-Euro filter smooths primary signals; vibrato band-pass runs on pitch stream (~0.1ms).
4. Theremin mapping produces MIDI events + overlay state (~0.01ms).
5. Events go out with timestamp T; overlay state hits the main thread for the next display refresh.
6. If tracking takes longer than the frame budget, the frame is dropped and a counter ticks (visible in the HUD).

## 6. Latency Budget (30fps worst case, 60fps best)

| Stage | Budget |
|---|---|
| Camera exposure+readout | 8–16ms (hardware, not controllable) |
| Vision hand pose | 3–8ms |
| Filter+mapping | <1ms |
| CoreMIDI delivery | <1ms |
| **Pipeline total** | **12–26ms** |
| End-to-end perceived | 15–40ms |

Reference: 15–40ms is in the same band as playing a MIDI keyboard through a software instrument — acceptable for expressive continuous control. Tuning goal: keep pipeline <26ms at 30fps on M4 Max.

## 7. Performance & Testing

- **Bench mode** (debug build): logs per-stage timings every second, frame-drop counter, Vision vs. total budget. First PR includes this; we tune One-Euro params against real footage.
- Unit tests: One-Euro filter (synthetic noisy sine → verify lag/jitter trade), vibrato band separation, pinch hysteresis, scale quantization, mapping state machine (note-on/off transitions, volume floor).
- Component/manual: scripted QA checklist in the repo (camera on, both hands detected, zones set, Logic receives notes, practice toggle silent, instrument switch clean).
- CI: unit tests on macOS runner per PR; tag `v*` → release workflow (build, sign, notarize, DMG, GitHub Release) mirroring ltx-video-mac.

## 8. Key Technical Risks & Mitigations

1. **Pitch bend resolution (MIDI 1.1, ±2 semis = ~4096 steps / 200 cents ≈ 5 cents/step).** Audible as faint zipper on slow glissandi on very clean timbres. Mitigations: send coarse+fine bend (14-bit is the standard anyway), scale quantization mode makes steps consonant, MPE in v2 removes the ceiling entirely.
2. **Vision latency spikes on detection loss** (hand leaves frame → re-detect stall). Mitigation: frame-drop policy + note-off on hand-lost (no stuck notes), confidence gate before gate events.
3. **Jitter vs. latency** (classic filter trade). Mitigation: One-Euro is explicitly designed for this; params tuned in bench mode, per-instrument presets.
4. **Apple Vision pose not positionally stable frame-to-frame at range.** Mitigation: One-Euro + rejection of low-confidence frames; if insufficient, fall back plan is MediaPipe Hands (same landmark count) behind the same `HandTracker` protocol.
5. **Logic mapping confusion** (pitch bend range per instrument varies). Mitigation: README quick-start with Alchemy; app exposes "bend range" setting to match the instrument patch.

## 9. Repository Layout

```
sleight/
  sleight.xcodeproj
  sleight/               # app target
    App/                 # entry, SwiftUI shell
    Capture/             # AVCapture pipeline
    Tracking/            # Vision hand tracker (protocol + Vision impl)
    Filtering/           # One-Euro, vibrato engine
    Instruments/         # Instrument protocol, Theremin, registry
    MIDI/                # CoreMIDI source, event model
    Synth/               # AVAudioEngine test synth
    UI/                  # overlay Metal view, HUD, settings
    Support/             # calibration store, presets
  sleightTests/          # unit tests (filter, vibrato, mapping)
  .github/workflows/     # ci.yml, release.yml
  docs/superpowers/specs # this file
  README.md
```

## 10. Milestones

1. **M1 — Camera + skeleton overlay.** Live view with hand skeletons drawn. (The feedback loop exists before any MIDI.)
2. **M2 — Filter + theremin mapping, silent.** Values drive on-screen cursor/levels; bench timings captured.
3. **M3 — MIDI out.** Notes sound in Logic; pitch/volume/gate/mod all live; test synth playable.
4. **M4 — Calibration + polish.** Zone setup UX, practice toggle, presets, HUD, QA pass.
5. **M5 — Release.** README, CI release workflow, signed/notarized DMG, v0.1.0 tag.

## 11. Open Questions (resolve during build, not blockers)

- Exact Vision hand-pose throughput at 1280×720 on M4 Max (bench in M1/M2).
- Logic's MPE-record behavior with Alchemy (only matters for v2).
- Whether 60fps capture via Continuity Camera (iPhone) is worth supporting early — likely yes for demo videos, later milestone.

## 12. Branding

- Name: **Sleight** (confirmed). Domain: sleightapp.xyz (purchased). GitHub: `james-see/sleight`.
- Tagline: "Sleight of hand for your DAW."
- Logo direction (later): a hand forming a pinch gesture over a waveform; minimal line art.