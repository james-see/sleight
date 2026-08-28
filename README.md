# Sleight

*Sleight of hand for your DAW.*

Sleight is a native macOS app that turns hand and finger movement — tracked from
your webcam at 21 landmarks per hand via Apple Vision — into expressive MIDI.
No gloves, no sensors, no calibration ritual. Your hands are the controller.

https://sleightapp.xyz

## Quickstart (20 seconds)

1. Open Sleight. Allow camera access.
2. In Logic Pro (or any DAW), pick **Sleight** as the MIDI input on an instrument track.
3. Play:
   - **Right hand** moves horizontally → pitch (quantized to your chosen scale, or free)
   - **Left hand** moves vertically → volume (drop it low to mute)
   - **Pinch** (thumb + index) → note on/off
   - **Wave your hand** at singing-vibrato speed (4–8 Hz) → real vibrato; slow drift is filtered out
4. No DAW open? Toggle off **Practice (silent)** and the built-in synth sounds instead.

## Instruments

| Instrument | Status | Control scheme |
|---|---|---|
| Theremin | ✅ v1 | right-hand X → pitch · left-hand Y → volume · pinch → gate · 4–8 Hz oscillation → vibrato |
| Ribbon | 🔜 v2 | 1D pitch strip + pressure |
| Keyboard grid | 🔜 later | novelty mode — a real keybed still wins for fast runs |

## Latency

Camera-to-MIDI pipeline budget on Apple Silicon (see
`docs/superpowers/specs/2026-08-27-sleight-design.md` §6):

| Stage | Cost |
|---|---|
| Camera exposure + readout | 8–16 ms (hardware) |
| Vision hand pose (ANE) | 3–8 ms |
| One-Euro filter + mapping | < 1 ms |
| CoreMIDI delivery | < 1 ms |
| **End-to-end perceived** | **15–40 ms** |

That's the same band as a MIDI keyboard through a software instrument.

## Requirements

- macOS 14+, Apple Silicon (M1 or newer)
- Any webcam (built-in FaceTime HD is fine)
- A DAW or hardware synth that accepts MIDI (only if you want sound beyond the test synth)

## Building from source

```bash
brew install xcodegen
git clone https://github.com/james-see/sleight && cd sleight
xcodegen
open sleight.xcodeproj   # ⌘R
```

## How it works

```
Camera (30–60fps) → Vision hand pose (21 pts × 2 hands, ANE) → One-Euro filter
  → instrument mapping (pluggable) → CoreMIDI virtual source "Sleight"
                                    ↘ SwiftUI Canvas overlay (skeleton, zones, pinch ring)
```

The pipeline never queues frames (stale frames are useless for a real-time
instrument), drops work when tracking falls behind, and every MIDI event is
timestamped from the camera frame's host time. Hands leaving the frame always
fire a note-off — no stuck notes, ever.

## Roadmap

- v2: MPE / MIDI 2.0 output (per-note pitch bend at full resolution), AUv3 plugin, ribbon instrument
- v3: ESP32 wireless-glove mode (IMU-fused tracking for away-from-desk play)

## License

MIT — see [LICENSE](LICENSE).