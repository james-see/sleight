# Sleight v2 Design: MIDI 2.0 Protocol Layer + Glide

**Date:** 2026-08-28
**Status:** Approved design, pending implementation
**Depends on:** v1 (`docs/superpowers/specs/2026-08-27-sleight-design.md`), shipped and working

---

## 1. Summary

v2 upgrades Sleight's MIDI output from MIDI 1.1 bytes to a selectable protocol layer:

- **MIDI 2.0 (UMP)** — default. 16-bit note velocity, 32-bit per-note pitch bend, per-note bend range set by explicit RPN (no receiver-default guessing).
- **MPE (MIDI 1.1)** — first-class fallback. Note events + per-note bend on channel 2, global CC on channel 1, MPE configuration sent at init.
- **MIDI 1.1** — today's exact behavior (byte-compatible results via the same UMP send path).
- **Glide mode** — the release's headline feature: while a note is held (pinched), sounding pitch glides continuously with hand motion instead of re-articulating at each scale tone. UMP/MPE only.

Out of scope (deferred): AUv3 plugin, ribbon instrument, poly-per-finger (v2.1 seam is laid by §4.1), portamento glide variant, MIDI-CI auto-negotiation.

## 2. Background: v1 behavior being upgraded

- `MIDISource` sends MIDI 1.1 byte packets via the legacy `MIDIPacketList` API (`sleight/MIDI/MIDISource.swift`).
- `MIDIEvent.Kind` is channel-blind: `noteOn(UInt8, velocity: UInt8)`, `pitchBendSemitones(Double)` (not attached to a note), `noteOff(UInt8)`, `cc(UInt8, UInt8)`.
- `Theremin` is monophonic: pitch = quantized scale tone from right index-tip x; vibrato taps pre-quantization pitch and rides the bend channel; crossing a scale tone while pinched re-articulates (noteOff + new noteOn, `Theremin.swift:107-115`); velocity = 7-bit map of pinch closeness; volume = CC7 from left wrist y.
- End-to-end latency budget and drop policy are untouched by v2.

Resolution facts (correct numbers, for the record):
- v1 stepped bend: 8191 units over ±2 semis = **0.24 cents/unit** (already excellent; the problem is range and articulation, not resolution).
- MPE per-note bend: 8191 units over ±48 semis = 170.7 units/semitone = **5.9 cents/unit** (smooth to every ear).
- UMP per-note bend: 32-bit over ±24 semis ≈ 8.9e7 units/semitone = **1.1e-6 cents/unit** (inaudible quantization).
- Glide capability, not bit depth, is why UMP/MPE matter for this instrument.

## 3. Protocol modes (settings picker)

Picker in ContentView: **“MIDI 2.0 (UMP)” (default) / “MPE (MIDI 1.1)” / “MIDI 1.1”**. Persisted in `AppSettings` (`midiMode: ump | mpe | legacy`).

Mode switch destroys and recreates the virtual source via `MIDISourceCreateWithProtocol` (many hosts enumerate sources once). Creation failure → revert to last-good mode, surface error on the diagnostic card. Endpoint name stays `"Sleight"` in all modes.

| | UMP | MPE | MIDI 1.1 |
|---|---|---|---|
| CoreMIDI protocol | `kMIDIProtocol_2_0` | `kMIDIProtocol_1_0` | `kMIDIProtocol_1_0` |
| Send path | `MIDIEventList` / `MIDIReceivedEventList` | same | same |
| Note channels | 1 | 1 global / 2 notes | 1 |
| Velocity | 16-bit | 7-bit | 7-bit |
| Bend | per-note, 32-bit, RPN 0 = ±2 (stepped) / ±24 (glide) | per-note ch2, fixed ±48 | channel bend, ±2 |
| Glide | yes | yes | no (picker grays it out; stepped forced) |
| CC7 | ch1, 32-bit (`cc7 << 25`) | ch1 | ch1 |

## 4. Design

### 4.1 Event model (`Core/Types.swift`)

```swift
public enum Kind: Equatable {
    case noteOn(note: UInt8, velocity: Double)          // velocity = 0…1 pinch closeness
    case noteOff(note: UInt8)
    case perNotePitchBendSemitones(note: UInt8, Double) // attached to the sounding note
    case cc(UInt8, UInt8)                               // unchanged (global, 0-127)
}
```

- Velocity becomes `Double` 0–1 so the UMP encoder gets full precision; MPE/1.1 encoders round to 7-bit exactly as v1 did.
- Bend is now per-note — today it is already mathematically note-scoped (one held note); the type now says so. This is the seam v2.1 polyphony plugs into.
- Timestamps and the `Instrument` protocol are unchanged. Theremin computes exactly what it computed in v1 plus §4.4.

### 4.2 `MIDISource` rework

Single send path for all modes: one `MIDIEventList` scratch buffer, `MIDIEventListInit`/`MIDIEventListAdd` per event, `MIDIReceivedEventList` (timestamp = now, as v1). The `MIDIPacketList` code is deleted. Encoding lives in a new pure, testable file `MIDI/UMPEncoder.swift` — no CoreMIDI client state needed to unit-test words.

- **UMP mode**: `MIDI2NoteOn/Off` (16-bit velocity = `Double * 65535`), `MIDI2PerNotePitchBend` (32-bit: `(0.5 + semis/bendRange) * 2³²`, clamped, `0x80000000` = no bend), `MIDI2ControlChange`. RPN 0 (bend range) sent at source creation and on bend-range setting change, encoded as 7-bit-compatible 32-bit CC words (`value = cc7 << 25`).
- **MPE mode**: init sequence on ch1 — MPE configuration RPN 6 with data-entry 1 (one member channel → ch2), then bend-range RPN 0 = 48 on ch1 (belt-and-braces per MPE spec recommendations), each RPN frame followed by RPN null (CC101/100 = 127). Notes + per-note bend (±48 scale) on ch2; CC7 global on ch1.
- **Legacy mode**: byte streams identical to v1, expressed via `MIDI1UP*` 32-bit words (`MIDI1UPNoteOn`, `MIDI1UPPitchBend`, `MIDI1UPControlChange`).

Sender-side clamp (`min/max` on semitones vs. mode bend range) lives in the encoder, not the instrument.

### 4.3 TestSynth & practice mode

Both listen to the pre-encoder event stream; they gain the new `Kind` cases (velocity import as `Double`, per-note bend read directly). Practice mode passes events only to `TestSynth` — unaffected. `TestSynth` gets the glide behavior for free since it consumes raw events.

### 4.4 Glide (Theremin)

New toggle `glideMode: stepped | glide` (default **glide**; forced to and locked at stepped in legacy mode).

- **Articulation** (pinch-down, or re-pinch after gate close): piston as in v1 — `noteOn` at the *quantized* nearest scale tone, velocity from pinch closeness. The scale still decides where notes start; you always land in key.
- **While held**: no re-articulation, ever. The bend target switches from v1's `quantized − base` to `raw − base` (unquantized hand position), so sounding pitch = continuous hand position, theremin-style. Vibrato (`VibratoEngine`, taps pre-quantization raw) adds on top unchanged.
- **Bend range by mode**: glide needs the full band inside one note's range — 2-octave band max offset = 24 semis → RPN 0 = **±24 in UMP glide**, ±2 in UMP stepped, ±48 fixed in MPE (24 fits), ±2 in legacy.
- **Gate close** (pinch release, volume floor, hand lost): `noteOff`, then bend reset — UMP: per-note bend `0x80000000` on that note; MPE: channel bend center `0x2000` on ch2 — so a later re-articulation on the same note/channel can't inherit a stale wild bend. No `cc7=0` on close when gliding (volume is held, not floored).
- Stepped mode = exact v1 behavior (re-articulate at tone crossings), at UMP resolution when in UMP mode.

### 4.5 Settings & UI

`AppSettings` gains `midiMode` and `glideMode` (UserDefaults-backed, existing pattern). ContentView: protocol picker + glide toggle (disabled in legacy mode). Mode change → `SleightController` recreates the source; bend-range setting change → re-send RPN 0 (UMP). No other UI churn; overlay unchanged.

## 5. Files changed

| File | Change |
|---|---|
| `Core/Types.swift` | `Kind` reshape (§4.1) |
| `MIDI/UMPEncoder.swift` | **new** — pure per-mode encoding + RPN sequences |
| `MIDI/MIDISource.swift` | `MIDISourceCreateWithProtocol`, event-list send path, recreate-on-mode-change, delete `MIDIPacketList` path |
| `Instruments/Theremin.swift` | `Double` velocity, `perNotePitchBendSemitones`, glide logic |
| `Synth/TestSynth.swift` | new `Kind` cases |
| `Support/Settings.swift` | `midiMode`, `glideMode` |
| `App/ContentView.swift`, `App/SleightController.swift` | pickers, wiring |
| `sleightTests/*` | `MIDIEventTests` update; **new** `UMPEncoderTests`; `ThereminTests` glide + velocity; mechanical updates elsewhere |
| `README.md` | protocol table, glide docs, roadmap update (same PR as code) |

## 6. Testing

**Unit (word-level, pure):** encoder outputs asserted against SDK inline helpers as oracles — `MIDI2PerNotePitchBend(0, 0, note, expected)`, `MIDI1UPNoteOn(0, 0, n, v)`, `MIDI2ControlChange(...)`. Cases: velocity Double→16-bit/7-bit paths, bend clamp at ±range and at 0.5-semi offsets, `0x80000000` no-bend word, `cc7 << 25`, MPE init word list (RPN 6 → member 1, RPN null, RPN 0 = 48), UMP RPN 0 by glide/stepped mode, legacy byte-identical vectors (capture v1 outputs as fixtures).

**Behavior (Theremin/glide):** glide holds one note across N scale tones (no noteOff/On in stream), articulation snaps to quantized tone, gate-close emits bend reset, band-edge clamp, legacy mode forces stepped, velocity boundary values (0.0 → min, 1.0 → 127/65535).

**Live verification checklist (manual, pre-release):**
1. Logic 11, UMP mode: “Sleight” listed as MIDI 2.0 source; record glide — continuous pitch curve, no re-triggers; 16-bit velocities visible in note editor.
2. Logic 11, MPE mode: per-note bend recorded as MPE expression; glide works.
3. Legacy mode: MIDI Monitor byte-diff against v1 capture.
4. Any second DAW/GS napkin check (e.g. Ableton) for MPE sanity.
Items 1–3 gate release; the UMP-into-Logic path is the only thing unit tests cannot prove.

## 7. Risks & mitigations

- **Logic UMP maturity** (per-note bend over UMP may be lossy in 2026 hosts) → MPE mode is a first-class fallback, not an afterthought; live checklist gates release.
- **Hosts listing only MIDI 1.0 sources despite protocol flag** → recreate-on-mode-change is the user-facing fix; README documents it.
- **Stale bend on re-articulation** → explicit reset on gate close (§4.4), covered by tests.
- **Scope creep** → polyphony, portamento, AUv3, ribbon explicitly deferred; §4.1 keeps the door open without building them.

## 8. Non-goals (parked)

- Per-finger polyphony (v2.1) — seam: per-note event attribution ships in §4.1.
- Portamento glide (glide-to-then-lock-quantized) — glide follows raw hand position, theremin-style; revisit if play-testing wants it.
- MIDI 2.0.1 feature set beyond CV messages (JRTimestamps, SysEx8, CI profiles).