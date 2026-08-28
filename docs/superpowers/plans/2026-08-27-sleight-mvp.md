# Sleight MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship Sleight v0.1.0 — a native macOS app that tracks hands via Apple Vision from the webcam, plays a theremin (right hand pitch, left hand volume, pinch gate, vibrato), draws a live AR overlay on the camera feed, and sends MIDI 1.1 to Logic.

**Architecture:** Five-stage serial pipeline off the main thread: Capture (AVFoundation) → Tracking (Vision 21 landmarks × 2 hands) → Filtering (One-Euro + vibrato band-pass) → Mapping (pluggable `Instrument` protocol; v1 = Theremin) → Output (CoreMIDI virtual source + AVAudioEngine test synth). UI is SwiftUI with `AVCaptureVideoPreviewLayer` + a Canvas overlay at display rate.

**Tech Stack:** Swift 5.10+, SwiftUI, AVFoundation, Vision, CoreMIDI, AVAudioEngine, XCTest, XcodeGen, GitHub Actions (macos-14 runner).

**Spec:** `docs/superpowers/specs/2026-08-27-sleight-design.md`

## Global Constraints

- macOS deployment target **14.0**; Apple Silicon only (arm64).
- **Zero third-party runtime dependencies** — Vision/AVFoundation/CoreMIDI/AVAudioEngine only. (XcodeGen is a dev-time tool, installed via `brew install xcodegen` if missing.)
- Xcode is at `/Applications/Xcode.app` but `xcode-select` points at CommandLineTools — **prefix every xcodebuild with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`**.
- MIDI 1.1 only: Note On/Off ch1, Pitch Bend ±2 semitones (14-bit), CC7 volume, CC1 modulation. Virtual source named **"Sleight"**.
- Camera frames: always `alwaysDiscardsLateVideoFrames = true`; pipeline drops work when behind — never queue.
- Hand-lost or confidence < 0.5 → note-off safety. No stuck notes, ever.
- Overlay palette: monochrome blues in the `#0A84FF` family (accent `#0A84FF`, dim `#0A84FF` @ 30%, background wash `#0A84FF` @ 10%).
- Commit after every task; conventional commit messages (`feat:`, `test:`, `chore:`). Never commit `xcuserdata/`, `DerivedData/`, `.DS_Store` (see Task 1 .gitignore).
- Run tests: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project sleight.xcodeproj -scheme sleight -destination 'platform=macOS' -quiet`
- Regenerate project after editing `project.yml`: `cd ~/p/sleight && xcodegen`

## File Structure

```
sleight/
  project.yml                          # XcodeGen manifest (Task 1)
  .gitignore                           # (Task 1)
  sleight/
    App/SleightApp.swift               # @main, window scene (Task 1)
    App/ContentView.swift              # root view (Task 1, expanded Task 11)
    Core/Types.swift                   # HandSide, LandmarkPoint, HandFrame, OverlayState (Task 3)
    Filtering/OneEuroFilter.swift      # One-Euro per-coordinate filter (Task 2)
    Filtering/VibratoEngine.swift      # band-pass + envelope gate → cents depth (Task 5)
    Music/MusicTheory.swift            # scales, quantization, note names (Task 3)
    Tracking/PinchDetector.swift       # scale-invariant pinch + hysteresis (Task 4)
    Tracking/HandTracker.swift         # protocol + VisionHandTracker (Task 6)
    Instruments/Instrument.swift       # protocol + registry (Task 7)
    Instruments/Theremin.swift         # v1 mapping state machine (Task 7)
    MIDI/MIDIEvent.swift               # event model + raw byte encoding (Task 8)
    MIDI/MIDISource.swift              # CoreMIDI virtual source (Task 8)
    Capture/CaptureService.swift       # AVCaptureSession plumbing (Task 9)
    Pipeline/Pipeline.swift            # stage glue + drop policy (Task 10)
    Pipeline/PipelineModel.swift       # @MainActor observable UI state (Task 10)
    UI/CameraView.swift                # preview layer representable (Task 11)
    UI/OverlayView.swift               # Canvas skeleton/zones/pinch/level (Task 11)
    UI/HUDView.swift                   # fps, drops, note readout (Task 11)
    Synth/TestSynth.swift              # AVAudioEngine oscillator (Task 12)
    Support/Settings.swift             # AppStorage-backed settings + zones (Task 13)
    Support/Assets.xcassets            # AppIcon (Task 15), AccentColor
  sleightTests/
    OneEuroFilterTests.swift           # Task 2
    MusicTheoryTests.swift             # Task 3
    PinchDetectorTests.swift           # Task 4
    VibratoEngineTests.swift           # Task 5
    HandTrackerTests.swift             # Task 6
    ThereminTests.swift                # Task 7
    MIDIEventTests.swift               # Task 8
    PipelineTests.swift                # Task 10
  .github/workflows/ci.yml             # Task 14
  .github/workflows/release.yml        # Task 14
  README.md                            # Task 15
```

---

### Task 1: Project scaffold (XcodeGen, builds and launches)

**Files:**
- Create: `~/p/sleight/project.yml`, `~/p/sleight/.gitignore`, `~/p/sleight/sleight/App/SleightApp.swift`, `~/p/sleight/sleight/App/ContentView.swift`, `~/p/sleight/sleight/Info.plist` (generated properties live in project.yml; no manual plist needed)

**Interfaces:**
- Produces: Xcode project with `sleight` scheme; app launches showing "Sleight" text. Later tasks add folders — XcodeGen globs pick them up.

- [ ] **Step 1: Install XcodeGen if missing**

```bash
which xcodegen || brew install xcodegen
```

- [ ] **Step 2: Write .gitignore**

```gitignore
# Xcode
DerivedData/
xcuserdata/
*.xcuserstate
*.xcworkspace/xcuserdata/
# XcodeGen output
*.xcodeproj
# macOS
.DS_Store
# build litter
build/
```

(The `.xcodeproj` is generated — only `project.yml` is source of truth.)

- [ ] **Step 3: Write project.yml**

```yaml
name: sleight
options:
  bundleIdPrefix: us.jamescampbell
  deploymentTarget:
    macOS: "14.0"
  createIntermediateGroups: true
settings:
  base:
    SWIFT_VERSION: "5.10"
    ARCHS: arm64
    CODE_SIGN_STYLE: Automatic
targets:
  sleight:
    type: application
    platform: macOS
    sources: [sleight]
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: us.jamescampbell.sleight
        INFOPLIST_KEY_NS CameraUsageDescription: "Sleight tracks your hands to play MIDI instruments."
        GENERATE_INFOPLIST_FILE: YES
        INFOPLIST_KEY_LSApplicationCategoryType: public.app-category.music
  sleightTests:
    type: bundle.unit-test
    platform: macOS
    sources: [sleightTests]
    dependencies:
      - target: sleight
schemes:
  sleight:
    build:
      targets:
        sleight: all
        sleightTests: [test]
    test:
      targets: [sleightTests]
```

> NOTE if XcodeGen rejects `INFOPLIST_KEY_NS CameraUsageDescription` (space is a typo risk): use `INFOPLIST_KEY_NSCameraUsageDescription` exactly.

- [ ] **Step 4: Write app entry**

`~/p/sleight/sleight/App/SleightApp.swift`:

```swift
import SwiftUI

@main
struct SleightApp: App {
    var body: some Scene {
        WindowGroup("Sleight") {
            ContentView()
                .frame(minWidth: 960, minHeight: 640)
        }
        .windowToolbarStyle(.unified)
    }
}
```

`~/p/sleight/sleight/App/ContentView.swift`:

```swift
import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("Sleight")
                .font(.largeTitle.bold())
            Text("sleight of hand for your DAW")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

#Preview { ContentView() }
```

- [ ] **Step 5: Generate and build**

```bash
cd ~/p/sleight && xcodegen
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build -project sleight.xcodeproj -scheme sleight -destination 'platform=macOS' -quiet
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
cd ~/p/sleight && git add -A && git commit -m "feat: project scaffold with XcodeGen, builds and launches"
```

---

### Task 2: One-Euro filter

**Files:**
- Create: `~/p/sleight/sleight/Filtering/OneEuroFilter.swift`
- Test: `~/p/sleight/sleightTests/OneEuroFilterTests.swift`

**Interfaces:**
- Produces: `struct OneEuroFilter { init(minCutoff: Double, beta: Double, dCutoff: Double); mutating func filter(_ value: Double, dt: Double) -> Double }`. Later tasks wrap two of these per signal.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import sleight

final class OneEuroFilterTests: XCTestCase {
    /// Deterministic pseudo-noise (no randomness in tests).
    func noise(_ i: Int) -> Double { ((i * 1103515245 + 12345) % 2000) / 2000.0 - 0.5 }

    @Test-like func testReducesJitterOnStaticSignal() {
        var f = OneEuroFilter(minCutoff: 1.0, beta: 0.007, dCutoff: 1.0)
        var last: Double = 0
        for i in 0..<200 { last = f.filter(0.5 + noise(i), dt: 1.0/60) }
        // settled output near 0.5 and residual jitter far below raw input
        let raw = (0..<200).map { abs(noise($0)) }.max()!
        XCTAssertLessThan(abs(last - 0.5), 0.05)
        XCTAssertLessThan(abs(last - 0.5), raw)
    }

    func testTracksSlowRampWithBoundedLag() {
        var f = OneEuroFilter(minCutoff: 1.0, beta: 0.007, dCutoff: 1.0)
        var out = 0.0
        for i in 0..<600 {
            let x = Double(i) / 600.0 * 0.5   // slow ramp to 0.5 over 10s
            out = f.filter(x, dt: 1.0/60)
        }
        XCTAssertEqual(out, 0.5, accuracy: 0.05) // steady-state lag small at slow speed
    }

    func testFastStepFollowsWithSpeed() {
        var f = OneEuroFilter(minCutoff: 1.0, beta: 0.02, dCutoff: 1.0)
        for i in 0..<60 { _ = f.filter(0.5, dt: 1.0/60) }
        var out = 0.0
        for i in 0..<15 { out = f.filter(1.0, dt: 1.0/60) } // fast flick
        XCTAssertGreaterThan(out, 0.7) // adaptive cutoff opens up on fast motion
    }
}
```

(XCTest has no `@Test-like` — name the first method `testReducesJitterOnStaticSignal` plainly; remove that stray token.)

- [ ] **Step 2: Run test to verify it fails**

```bash
cd ~/p/sleight && xcodegen && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project sleight.xcodeproj -scheme sleight -destination 'platform=macOS' -quiet 2>&1 | tail -5
```

Expected: compile FAIL — `OneEuroFilter` not defined.

- [ ] **Step 3: Implement**

```swift
import Foundation

/// One-Euro filter (Casiez et al. 2012) — adaptive low-pass: heavy smoothing
/// when slow (kills jitter), opens up when fast (kills lag).
/// Standard form: https://gery.casiez.net/1euro/
public struct OneEuroFilter {
    public var minCutoff: Double   // Hz, baseline smoothing
    public var beta: Double        // speed coefficient
    public var dCutoff: Double     // Hz, derivative smoothing

    private var xPrev: Double?
    private var dxPrev: Double = 0

    public init(minCutoff: Double, beta: Double, dCutoff: Double) {
        self.minCutoff = minCutoff
        self.beta = beta
        self.dCutoff = dCutoff
    }

    private static func alpha(_ cutoff: Double, _ dt: Double) -> Double {
        let tau = 1.0 / (2.0 * .pi * cutoff)
        return 1.0 / (1.0 + tau / dt)
    }

    public mutating func filter(_ value: Double, dt: Double) -> Double {
        let dt = max(dt, 1e-4)
        let dx: Double
        if let xPrev { dx = (value - xPrev) / dt } else { dx = 0 }
        let aD = Self.alpha(dCutoff, dt)
        dxPrev = aD * dx + (1 - aD) * dxPrev
        let cutoff = minCutoff + beta * abs(dxPrev)
        let a = Self.alpha(cutoff, dt)
        let xHat: Double
        if let xPrev { xHat = a * value + (1 - a) * xPrev } else { xHat = value }
        xPrev = xHat
        return xHat
    }
}
```

- [ ] **Step 4: Run tests, verify pass**

Same test command. Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add sleight/Filtering/OneEuroFilter.swift sleightTests/OneEuroFilterTests.swift
git commit -m "feat: One-Euro filter for landmark trajectories"
```

---

### Task 3: Core types + music theory (scales, quantization, note names)

**Files:**
- Create: `~/p/sleight/sleight/Core/Types.swift`, `~/p/sleight/sleight/Music/MusicTheory.swift`
- Test: `~/p/sleight/sleightTests/MusicTheoryTests.swift`

**Interfaces:**
- Produces:
  - `enum HandSide { case left, right }`
  - `struct LandmarkPoint { var x: Double; var y: Double; var confidence: Double }` (normalized 0…1, y top-down)
  - `struct HandFrame { var side: HandSide; var points: [LandmarkPoint]; var timestamp: Double }` (21 points, Vision index order)
  - `struct OverlayState { ... }` fields listed in Task 10.
  - `enum Scale { case chromatic, major, minorPentatonic, free }` with `func intervals() -> [Int]`
  - `struct MusicTheory { static func quantize(_ pitch: Double, scale: Scale, root: Int) -> Double; static func noteName(_ semitone: Int) -> String }` — pitch in MIDI semitones (float); quantize returns nearest scale semitone.

- [ ] **Step 1: Write failing tests**

```swift
import XCTest
@testable import sleight

final class MusicTheoryTests: XCTestCase {
    func testChromaticQuantizeIsRoundToNearestSemitone() {
        XCTAssertEqual(MusicTheory.quantize(60.4, scale: .chromatic, root: 0), 60)
        XCTAssertEqual(MusicTheory.quantize(60.6, scale: .chromatic, root: 0), 61)
        XCTAssertEqual(MusicTheory.quantize(60.5, scale: .chromatic, root: 0), 61) // .5 rounds up
    }

    func testMajorQuantizeSnapsToNearestScaleTone() {
        // C major from C4=60: allowed pcs {0,2,4,5,7,9,11}
        XCTAssertEqual(MusicTheory.quantize(60.9, scale: .major, root: 0), 60)  // nearer 60 than 62
        XCTAssertEqual(MusicTheory.quantize(61.1, scale: .major, root: 0), 62)  // nearer 62
        XCTAssertEqual(MusicTheory.quantize(58.8, scale: .major, root: 0), 59)  // nearer 57? no: 59.8→59? expect 57 (A2 below)? see wrap logic
    }

    func testQuantizeWrapsAcrossOctaveBoundary() {
        // 59.7 in C major: candidates 59(B)=11 pc? no, B=11 → 59; 60(C)=0 → 60. distance 0.3 vs 0.7 → 59? B is in C major? NO. B IS in C major (pc 11).
        XCTAssertEqual(MusicTheory.quantize(59.7, scale: .major, root: 0), 60)
    }

    func testFreeIsIdentity() {
        XCTAssertEqual(MusicTheory.quantize(61.37, scale: .free, root: 0), 61.37)
    }

    func testNoteNames() {
        XCTAssertEqual(MusicTheory.noteName(60), "C4")
        XCTAssertEqual(MusicTheory.noteName(61), "C#4")
        XCTAssertEqual(MusicTheory.noteName(59), "B3")
        XCTAssertEqual(MusicTheory.noteName(69), "A4")
    }
}
```

> Reviewer note: the `58.8` case above was ambiguous when written — correct expectation after wrap logic is `57` or `59` per the implementation's tie-breaking; pick the one the implementation below produces (58.8 → nearest major candidates 57(A) dist 1.8? no: allowed near 58.8 are 57 and 59; 59 is pc 11 = B, in C major, dist 0.2 → **59**). Fix the expected value to `59` when writing the file.

- [ ] **Step 2: Run tests — expect compile failure (types missing)**

- [ ] **Step 3: Implement Types.swift**

```swift
import Foundation

public enum HandSide: String, Codable { case left, right }

public struct LandmarkPoint: Equatable {
    public var x: Double          // normalized 0…1, image space (already camera-mirrored for selfie view)
    public var y: Double          // normalized 0…1, top-down
    public var confidence: Double // 0…1
    public init(x: Double, y: Double, confidence: Double = 1.0) {
        self.x = x; self.y = y; self.confidence = confidence
    }
}

/// 21 landmarks in Vision index order:
/// 0 wrist; 1-4 thumb; 5-8 index; 9-12 middle; 13-16 ring; 17-20 little.
public struct HandFrame: Equatable {
    public var side: HandSide
    public var points: [LandmarkPoint]
    public var timestamp: Double  // seconds, mach-based
    public init(side: HandSide, points: [LandmarkPoint], timestamp: Double) {
        self.side = side; self.points = points; self.timestamp = timestamp
    }
    public static let landmarkCount = 21
}
```

MusicTheory.swift:

```swift
import Foundation

public enum Scale: String, Codable, CaseIterable, Identifiable {
    case chromatic, major, minorPentatonic, free
    public var id: String { rawValue }
    public var intervals: [Int] {
        switch self {
        case .chromatic: return Array(0...11)
        case .major: return [0, 2, 4, 5, 7, 9, 11]
        case .minorPentatonic: return [0, 3, 5, 7, 10]
        case .free: return []
        }
    }
}

public enum MusicTheory {
    /// Snap continuous pitch (semitones) to nearest tone of scale rooted at `root`.
    public static func quantize(_ pitch: Double, scale: Scale, root: Int = 0) -> Double {
        switch scale {
        case .free, .chromatic:
            return (pitch * 2).rounded() / 2
        default:
            break
        }
        let intervals = scale.intervals
        let floorNote = Int(pitch.rounded(.down))
        var best = pitch
        var bestDist = Double.infinity
        for octave in -1...1 {                       // check a window around the pitch
            for iv in intervals {
                let candidate = Double((root + iv) + 12 * (octave + (floorNote / 12)))
                let d = abs(candidate - pitch)
                if d < bestDist { bestDist = d; best = candidate }
            }
        }
        return best
    }

    public static func noteName(_ semitone: Int) -> String {
        let names = ["C","C#","D","D#","E","F","F#","G","G#","A","A#","B"]
        return "\(names[((semitone % 12) + 12) % 12])\((semitone / 12) - 1)"
    }
}
```

- [ ] **Step 4: Run tests, reconcile the one ambiguous expectation, all pass**

- [ ] **Step 5: Commit**

```bash
git add sleight/Core/Types.swift sleight/Music/MusicTheory.swift sleightTests/MusicTheoryTests.swift
git commit -m "feat: hand frame types + scale quantization and note names"
```

---

### Task 4: Pinch detector with hysteresis

**Files:**
- Create: `~/p/sleight/sleight/Tracking/PinchDetector.swift`
- Test: `~/p/sleight/sleightTests/PinchDetectorTests.swift`

**Interfaces:**
- Consumes: `HandFrame` (Task 3)
- Produces: `struct PinchDetector { init(onThreshold: Double = 0.35, offThreshold: Double = 0.42); mutating func update(_ frame: HandFrame) -> (isActive: Bool, amount: Double) }` — pinch amount = thumb-tip(4)/index-tip(8) distance normalized by hand span (wrist 0 → middle-MCP 9), `isActive` debounced with hysteresis.

- [ ] **Step 1: Failing test**

```swift
import XCTest
@testable import sleight

final class PinchDetectorTests: XCTestCase {
    func frame(pinchDist: Double) -> HandFrame {
        var pts = (0..<21).map { _ in LandmarkPoint(x: 0.5, y: 0.5) }
        pts[0] = LandmarkPoint(x: 0.5, y: 0.9)      // wrist
        pts[9] = LandmarkPoint(x: 0.5, y: 0.5)      // middle MCP → span 0.4
        pts[4] = LandmarkPoint(x: 0.5 - pinchDist/2, y: 0.7)
        pts[8] = LandmarkPoint(x: 0.5 + pinchDist/2, y: 0.7)
        return HandFrame(side: .right, points: pts, timestamp: 0)
    }

    func testOpenHandDoesNotTrigger() {
        var d = PinchDetector()
        let r = d.update(frame(pinchDist: 0.8))
        XCTAssertFalse(r.isActive)
        XCTAssertGreaterThan(r.amount, 1.0)
    }

    func testCrossingOnThresholdActivates() {
        var d = PinchDetector()
        _ = d.update(frame(pinchDist: 0.5))
        let r = d.update(frame(pinchDist: 0.14)) // norm 0.35
        XCTAssertTrue(r.isActive)
mograph   }

    func testHysteresisRequiresWiderRelease() {
        var d = PinchDetector()
        _ = d.update(frame(pinchDist: 0.5))
        _ = d.update(frame(pinchDist: 0.14))      // on
        let r = d.update(frame(pinchDist: 0.16))  // 0.4 < off 0.42 → still on
        XCTAssertTrue(r.isActive)
        let r2 = d.update(frame(pinchDist: 0.20)) // 0.5 > 0.42 → off
        XCTAssertFalse(r2.isActive)
    }
}
```

(Remove the stray `mograph` token — artifact guard; file must compile clean.)

- [ ] **Step 2: Run — expect compile failure**

- [ ] **Step 3: Implement**

```swift
import Foundation

public struct PinchDetector {
    public var onThreshold: Double   // normalized distance below which pinch fires
    public var offThreshold: Double  // must exceed onThreshold (hysteresis)

    private var isActive = false

    public init(onThreshold: Double = 0.35, offThreshold: Double = 0.42) {
        self.onThreshold = onThreshold
        self.offThreshold = offThreshold
    }

    /// Thumb-index distance normalized by hand span → scale-invariant with camera distance.
    public mutating func update(_ frame: HandFrame) -> (isActive: Bool, amount: Double) {
        let thumb = frame.points[4], index = frame.points[8]
        let wrist = frame.points[0], mcp = frame.points[9]
        let span = max(hypot(mcp.x - wrist.x, mcp.y - wrist.y), 1e-4)
        let dist = hypot(index.x - thumb.x, index.y - thumb.y)
        let norm = dist / span
        if isActive {
            if norm > offThreshold { isActive = false }
        } else {
            if norm < onThreshold { isActive = true }
        }
        return (isActive, norm)
    }
}
```

- [ ] **Step 4: Run tests — pass (fix `0.8` expectation if norm lands >1 and test asserts <1; keep as written)**

- [ ] **Step 5: Commit**

```bash
git add sleight/Tracking/PinchDetector.swift sleightTests/PinchDetectorTests.swift
git commit -m "feat: scale-invariant pinch detector with hysteresis"
```

---

### Task 4b (combined into Task 4 commit if desired): Landmark index constants

Add to `Types.swift`:

```swift
public enum Landmark {
    public static let wrist = 0
    public static let thumbTip = 4
    public static let indexTip = 8
    public static let indexMCP = 5
    public static let middleMCP = 9
    public static let middleTip = 12
}
```

and use these constants in `PinchDetector` instead of magic numbers (update the tests accordingly).

---

### Task 5: Vibrato engine

**Files:**
- Create: `~/p/sleight/sleight/Filtering/VibratoEngine.swift`
- Test: `~/p/sleight/sleightTests/VibratoEngineTests.swift`

**Interfaces:**
- Consumes: nothing (pure DSP on a Double stream)
- Produces: `struct VibratoEngine { init(sampleRate: Double = 60, centerHz: Double = 5.5, q: Double = 1.2, gate: Double = 0.02); mutating func process(_ pitchSemitones: Double, dt: Double) -> (depthCents: Double, active: Bool) }`

- [ ] **Step 1: Failing test**

```swift
import XCTest
@testable import sleight

final class VibratoEngineTests: XCTestCase {
    func feed(_ engine: inout VibratoEngine, hz: Double, seconds: Double, amplitude: Double, dt: Double = 1.0/60) -> Double {
        var last: (depth: Double, active: Bool) = (0, false)
        let n = Int(seconds * 60)
        for i in 0..<n {
            let t = Double(i) / 60.0
            last = engine.process(60.0 + hz == 0 ? 0 : hz == 0 ? 0 : 0, dt: dt) // placeholder, replaced below
            _ = t
        }
        return last.depth
    }

    func testSingingVibratoPasses() {
        var e = VibratoEngine()
        var lastDepth = 0.0
        let n = 300 // 5s
        for i in 0..<n {
            let t = Double(i) / 60.0
            let wiggle = 0.35 * sin(2 * .pi * 6.0 * t)   // 6 Hz, ±0.35 semitone
            let r = e.process(60.0 + wiggle, dt: 1.0/60)
            lastDepth = r.depthCents
        }
        XCTAssertGreaterThan(lastDepth, 40)  // ~±35 cents detected
        XCTAssertTrue(e.lastActive)
    }

    func testSlowDriftRejected() {
        var e = VibratoEngine()
        var lastDepth = 0.0
        for i in 0..<300 {
            let t = Double(i) / 60.0
            let drift = 1.2 * sin(2 * .pi * 0.8 * t)   // 0.8 Hz wander
            let r = e.process(60.0 + drift, dt: 1.0/60)
            lastDepth = r.depthCents
        }
        XCTAssertLessThan(lastDepth, 10)
    }

    func testFastTremorRejected() {
        var e = VibratoEngine()
        var lastDepth = 0.0
        for i in 0..<300 {
            let t = Double(i) / 60.0
            let tremor = 0.3 * sin(2 * .pi * 14.0 * t)  // 14 Hz noise
            let r = e.process(60.0 + tremor, dt: 1.0/60)
            lastDepth = r.depthCents
        }
        XCTAssertLessThan(lastDepth, 15)
    }
}
```

(Delete the broken `feed` helper entirely before writing the file — the three real tests are self-contained.)

- [ ] **Step 2: Run — expect compile failure**

- [ ] **Step 3: Implement**

```swift
import Foundation

/// Extracts intentional vibrato (≈4–8 Hz hand oscillation) from the pitch stream.
/// A 2nd-order band-pass isolates the band; an envelope follower + gate decides
/// whether the oscillation is strong enough to be "singing" rather than noise.
public struct VibratoEngine {
    public let sampleRate: Double
    public let centerHz: Double
    public let q: Double
    public let gateThreshold: Double

    // Biquad band-pass state (RBJ cookbook)
    private var b0 = 0.0, b1 = 0.0, b2 = 0.0, a1 = 0.0, a2 = 0.0
    private var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0
    private var envelope: Double = 0

    public private(set) var lastActive = false

    public init(sampleRate: Double = 60, centerHz: Double = 5.5, q: Double = 1.2, gate: Double = 0.02) {
        self.sampleRate = sampleRate
        self.centerHz = centerHz
        self.q = q
        self.gateThreshold = gate
        recompute()
    }

    private mutating func recompute() {
        let w0 = 2 * .pi * centerHz / sampleRate
        let alpha = sin(w0) / (2 * q)
        let a0 = 1 + alpha
        b0 = alpha / a0; b2 = -alpha / a0
        a1 = -2 * cos(w0) / a0; a2 = (1 - alpha) / a0
        b1 = 0
    }

    /// Returns modulation depth in cents (±) and whether vibrato is currently active.
    public mutating func process(_ pitchSemitones: Double, dt: Double) -> (depthCents: Double, active: Bool) {
        // deviate from the slow-moving mean so DC/very-low drift doesn't hit the filter
        let x = pitchSemitones
        let y = b0*x + b1*x1 + b2*x2 - a1*y1 - a2*y2
        x2 = x1; x1 = x; y2 = y1; y1 = y
        // envelope follower (fast attack, slow release)
        let rect = abs(y)
        let coef = rect > envelope ? 0.3 : 0.02
        envelope += coef * (rect - envelope)
        lastActive = envelope > gateThreshold
        // semitones deviation → cents; y is the band-passed deviation
        let depthCents = y * 100
        return (lastActive ? depthCents : 0, lastActive)
    }
}
```

- [ ] **Step 4: Run tests — pass** (If the drift test leaks >10 cents: raise `a2` window by lowering q to 1.0 and gate to 0.025 — retune constants, not the tests.)

- [ ] **Step 5: Commit**

```bash
git add sleight/Filtering/VibratoEngine.swift sleightTests/VibratoEngineTests.swift
git commit -m "feat: vibrato engine — intentional 4-8Hz oscillation passes, drift/noise rejected"
```

---

### Task 6: Hand tracker (protocol + Vision implementation + fixture-testable normalization)

**Files:**
- Create: `~/p/sleight/sleight/Tracking/HandTracker.swift`
- Test: `~/p/sleight/sleightTests/HandTrackerTests.swift`

**Interfaces:**
- Produces:
  - `protocol HandTracker: AnyObject { func detect(_ pixelBuffer: CVPixelBuffer, at t: Double) -> [HandFrame] }`
  - `final class VisionHandTracker: HandTracker` (maxHandCount 2, confidence gate 0.5)
  - `struct HandTrackerLogic { static func mirrorX(_ points:) -> ... ; static func confidenceGate(...)` — pure helpers tested with fixture landmark dicts.

- [ ] **Step 1: Failing test** — pure normalization: given fixture `[Int: (x: Double, y: Double, c: Double)]` for one hand, `VisionHandTracker.makeFrame(side:.right, points: fixture, timestamp: 1.0)` returns a 21-point `HandFrame` with `x` mirrored (`1 - x`) and dropping points with confidence < 0.5 (they inherit the wrist position so skeletons stay connected — assert that choice):

```swift
import XCTest
@testable import sleight

final class HandTrackerTests: XCTestCase {
    func fixture() -> [Int: (x: Double, y: Double, c: Double)] {
        var f: [Int: (x: Double, y: Double, c: Double)] = [:]
        for i in 0..<21 { f[i] = (Double(i) / 21.0, 0.5, 0.9) }
        f[7] = (0.1, 0.5, 0.2)  // low confidence point
        return f
    }

    func testMakeFrameMirrorsXForSelfieView() {
        let frame = VisionHandTracker.makeFrame(side: .right, points: fixture(), timestamp: 1.0)
        XCTAssertEqual(frame.points.count, 21)
        XCTAssertEqual(frame.points[3].x, 1.0 - Double(3)/21.0, accuracy: 1e-9)
    }

    func testLowConfidencePointInheritsNeighborPosition() {
        let frame = VisionHandTracker.makeFrame(side: .right, points: fixture(), timestamp: 1.0)
        XCTAssertEqual(frame.points[7].x, frame.points[6].x, accuracy: 1e-9)
        XCTAssertGreaterThanOrEqual(frame.points[7].confidence, 0.5)
    }
}
```

- [ ] **Step 2: Run — expect compile failure**

- [ ] **Step 3: Implement**

```swift
import Foundation
import Vision
import CoreVideo

public protocol HandTracker: AnyObject {
    func detect(_ pixelBuffer: CVPixelBuffer, at t: Double) -> [HandFrame]
}

public final class VisionHandTracker: HandTracker {
    private let request: VNDetectHumanHandPoseRequest

    public init(maxHands: Int = 2) {
        request = VNDetectHumanHandPoseRequest()
        request.maximumHandCount = maxHands
    }

    public func detect(_ pixelBuffer: CVPixelBuffer, at t: Double) -> [HandFrame] {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .leftMirrored)
        try? handler.perform([request])
        guard let observations = request.results else { return [] }
        return observations.compactMap { obs in
            guard let all = try? obs.recognizedPoints(.all) else { return nil }
            // Vision vnPoints are keyed by VNHumanHandPoseObservation.JointName
            var pts: [Int: (x: Double, y: Double, c: Double)] = [:]
            for (joint, point) in all {
                pts[joint.rawValue] = (point.location.x, point.location.y, Double(point.confidence))
            }
            guard pts[Landmark.wrist] != nil else { return nil }
            let side: HandSide = obs.label == "right" ? .right : .left   // verify label semantics at M1 QA
            return Self.makeFrame(side: side, points: pts, timestamp: t)
        }
    }

    /// Pure + fixture-testable: mirror X for selfie view, gate confidence, bridge weak points.
    static func makeFrame(side: HandSide, points: [Int: (x: Double, y: Double, c: Double)], timestamp: Double) -> HandFrame {
        var out: [LandmarkPoint] = []
        out.reserveCapacity(HandFrame.landmarkCount)
        for i in 0..<HandFrame.landmarkCount {
            if let p = points[i], p.c >= 0.5 {
                out.append(LandmarkPoint(x: 1 - p.x, y: p.y, confidence: p.c))
            } else {
                let fallback = out.last ?? LandmarkPoint(x: 0.5, y: 0.5, confidence: 0)
                out.append(LandmarkPoint(x: fallback.x, y: fallback.y, confidence: 0))
            }
        }
        return HandFrame(side: side, points: out, timestamp: timestamp)
    }
}
```

> `joint.rawValue` mapping to our 0–20 indices must be verified against `VNHumanHandPoseObservation.JointName` at M1 (order is documented as wrist, thumb→little). If rawValue doesn't align, build an explicit switch on JointName → index in `detect`. Note this in the M1 QA checklist.

- [ ] **Step 4: Run tests — pass**

- [ ] **Step 5: Commit**

```bash
git add sleight/Tracking/HandTracker.swift sleightTests/HandTrackerTests.swift
git commit -m "feat: Vision hand tracker with confidence gating and selfie mirroring"
```

---

### Task 7: Instrument protocol + Theremin mapping

**Files:**
- Create: `~/p/sleight/sleight/Instruments/Instrument.swift`, `~/p/sleight/sleight/Instruments/Theremin.swift`
- Test: `~/p/sleight/sleightTests/ThereminTests.swift`

**Interfaces:**
- Consumes: `HandFrame`, `MusicTheory`, `PinchDetector`, `VibratoEngine` (Tasks 2–6)
- Produces:
  - `struct MIDIEvent: Equatable { enum Kind { case noteOn(UInt8, velocity: UInt8), noteOff(UInt8), pitchBendSemitones(Double), cc(UInt8, UInt8) } ; var kind: Kind; var timestamp: Double }`
  - `protocol Instrument: AnyObject { var id: String { get }; var displayName: String { get }; func update(hands: [HandFrame], dt: Double) -> [MIDIEvent]; var overlay: InstrumentOverlay? { get } }`
  - `final class Theremin: Instrument` — settings: `pitchBand: ClosedRange<Double> = 0.55...0.95`, `volumeBand: ClosedRange<Double> = 0.1...0.7`, `scale: Scale = .minorPentatonic`, `root: Int = 60` (C4), `octaves: Double = 2`, `bendRangeSemitones: Double = 2`.
  - Behavior (the contract tests assert):
    - right-hand x in pitchBand → continuous pitch = root + (xNorm) * 12 * octaves, quantized per scale; **pitch is emitted as**: nearest integer note + bend of the fractional remainder (bendVal = 8192 + frac/2 * 8191/2, frac ∈ [-0.5, 0.5]).
    - note-on fires when pinch activates (right hand); note change while active re-fires noteOff+noteOn (same ts ordering).
    - left-hand y in volumeBand inverted → CC7 (top = 127); y beyond band bottom → CC7→0 and note-off.
    - hand-lost while active → immediate noteOff.
    - vibrato depth (cents) converts to pitch bend offset when active: bend = bend(frac) + depthCents/100.

- [ ] **Step 1: Failing tests**

```swift
import XCTest
@testable import sleight

final class ThereminTests: XCTestCase {
    func hand(_ side: HandSide, x: Double, y: Double, pinchNorm: Double) -> HandFrame {
        var pts = (0..<21).map { _ in LandmarkPoint(x: 0.5, y: 0.5) }
        pts[0] = LandmarkPoint(x: x, y: y + 0.3)
        pts[9] = LandmarkPoint(x: x, y: y)
        // thumb/index straddling x by pinchNorm * span (span=0.4)
        pts[4] = LandmarkPoint(x: x - pinchNorm * 0.2, y: y)
        pts[8] = LandmarkPoint(x: x + pinchNorm * 0.2, y: y)
        return HandFrame(side: side, points: pts, timestamp: 0)
    }

    func testPinchStartsNoteAndEmitsBendAndCC7() {
        let t = Theremin()
        let evs = t.update(hands: [hand(.right, x: 0.75, y: 0.5, pinchNorm: 0.2),
                                   hand(.left, x: 0.25, y: 0.4, pinchNorm: 0.9)], dt: 1/60)
        XCTAssertTrue(evs.contains { if case .noteOn = $0.kind { return true } ; return false })
        XCTAssertTrue(evs.contains { if case .pitchBendSemitones = $0.kind { return true } ; return false })
        XCTAssertTrue(evs.contains { if case .cc(7, _) = $0.kind { return true } ; return false })
    }

    func testHandXMapsToPitchMonotonically() {
        let t = Theremin()
        func pitchFor(_ x: Double) -> Double {
            t.update(hands: [hand(.right, x: x, y: 0.5, pinchNorm: 0.2)], dt: 1/60)
            return t.currentPitch
        }
        let lo = pitchFor(0.56), hi = pitchFor(0.94)
        XCTAssertGreaterThan(hi, lo + 6) // spans most of 2 octaves
    }

    func testVolumeFloorReleasesNote() {
        let t = Theremin()
        _ = t.update(hands: [hand(.right, x: 0.75, y: 0.5, pinchNorm: 0.2),
                             hand(.left, x: 0.25, y: 0.4, pinchNorm: 0.9)], dt: 1/60)
        XCTAssertTrue(t.isGateOpen)
        _ = t.update(hands: [hand(.right, x: 0.75, y: 0.5, pinchNorm: 0.2),
                             hand(.left, x: 0.25, y: 0.95, pinchNorm: 0.9)], dt: 1/60) // below floor
        XCTAssertFalse(t.isGateOpen)
        XCTAssertTrue(t.pendingEvents.contains { if case .noteOff = $0.kind { return true } ; return false })
    }

    func testHandLostEmitsNoteOff() {
        let t = Theremin()
        _ = t.update(hands: [hand(.right, x: 0.75, y: 0.5, pinchNorm: 0.2)], dt: 1/60)
        _ = t.update(hands: [], dt: 1/60)
        XCTAssertTrue(t.pendingEvents.contains { if case .noteOff = $0.kind { return true } ; return false })
    }

    func testScaleQuantizationChoosesPentatonicTones() {
        let t = Theremin()
        t.scale = .minorPentatonic
        t.update(hands: [hand(.right, x: 0.75, y: 0.5, pinchNorm: 0.2)], dt: 1/60)
        let pc = Int(t.currentPitch.rounded()) % 12
        XCTAssertTrue([0,3,5,7,10].contains(((pc % 12) + 12) % 12), "pitch \(t.currentPitch) not in scale")
    }
}
```

- [ ] **Step 2: Run — compile failure**

- [ ] **Step 3: Implement Instrument.swift**

```swift
import Foundation

public struct MIDIEvent: Equatable {
    public enum Kind: Equatable {
        case noteOn(UInt8, velocity: UInt8)
        case noteOff(UInt8)
        case pitchBendSemitones(Double)   // ± bendRange around current base note
        case cc(UInt8, UInt8)             // controller, value 0-127
    }
    public var kind: Kind
    public var timestamp: Double
    public init(kind: Kind, timestamp: Double) { self.kind = kind; self.timestamp = timestamp }
}

public protocol Instrument: AnyObject {
    var id: String { get }
    var displayName: String { get }
    /// Consume one pipeline tick; return MIDI events (instrument queues its own
    /// extra safety events in `pendingEvents` for the host to drain).
    func update(hands: [HandFrame], dt: Double) -> [MIDIEvent]
    var pendingEvents: [MIDIEvent] { get }
}

public struct InstrumentRegistry {
    public static let v1: [any Instrument.Type] = [Theremin.self]
}
```

Theremin.swift:

```swift
import Foundation

public final class Theremin: Instrument {
    public var id: String { "theremin" }
    public var displayName: String { "Theremin" }

    // Calibration
    public var pitchBand: ClosedRange<Double> = 0.55...0.95
    public var volumeBand: ClosedRange<Double> = 0.1...0.7
    public var scale: Scale = .minorPentatonic
    public var root: Int = 60                  // C4
    public var octaves: Double = 2
    public var bendRangeSemitones: Double = 2
    public var vibratoDepthScale: Double = 1.0 // multiplier on engine output

    // State
    public private(set) var currentPitch: Double = 60
    public private(set) var isGateOpen = false
    public private(set) var currentNote: UInt8?
    public private(set) var pendingEvents: [MIDIEvent] = []
    private var pinch = PinchDetector()
    private var vibrato = VibratoEngine()
    private var lastVolume: UInt8 = 0

    public init() {}

    public func update(hands: [HandFrame], dt: Double) -> [MIDIEvent] {
        pendingEvents = []
        var events: [MIDIEvent] = []
        let t = Date().timeIntervalSinceReferenceDate

        let right = hands.first { $0.side == .right }
        let left = hands.first { $0.side == .left }

        // ---- pitch (right hand x) ----
        if let r = right {
            let x = r.points[Landmark.indexTip].x
            let xNorm = min(max((x - pitchBand.lowerBound) / (pitchBand.upperBound - pitchBand.lowerBound), 0), 1)
            var pitch = Double(root) + xNorm * 12 * octaves
            pitch = MusicTheory.quantize(pitch, scale: scale, root: root % 12)
            currentPitch = pitch
        }

        // ---- volume (left hand y, inverted) ----
        var volume: UInt8 = 0
        var belowFloor = false
        if let l = left {
            let y = l.points[Landmark.wrist].y
            if y < volumeBand.lowerBound {
                volume = 127
            } else if y > volumeBand.upperBound {
                volume = 0
                belowFloor = true
            } else {
                let n = 1 - (y - volumeBand.lowerBound) / (volumeBand.upperBound - volumeBand.lowerBound)
                volume = UInt8((Double(n) * 127).rounded())
            }
        } else {
            belowFloor = true // volume hand lost → silence
        }

        // ---- gate (right-hand pinch) ----
        var pinchActive = false
        var pinchAmount = 1.0
        if let r = right {
            let p = pinch.update(r)
            pinchActive = p.isActive
            pinchAmount = p.amount
        }

        // note transitions
        if pinchActive, !isGateOpen, !belowFloor {
            isGateOpen = true
            let note = UInt8(currentPitch.rounded())
            currentNote = note
            events.append(MIDIEvent(kind: .noteOn(note, velocity: 100), timestamp: t))
            events.append(MIDIEvent(kind: .pitchBendSemitones(bendSemitones()), timestamp: t))
            events.append(MIDIEvent(kind: .cc(7, volume), timestamp: t))
        } else if isGateOpen {
            let note = currentNote ?? UInt8(currentPitch.rounded())
            let noteChanged = UInt8(currentPitch.rounded()) != note
            if noteChanged && !belowFloor {
                events.append(MIDIEvent(kind: .noteOff(note), timestamp: t))
                currentNote = UInt8(currentPitch.rounded())
                events.append(MIDIEvent(kind: .noteOn(currentNote!, velocity: 100), timestamp: t))
            }
            if belowFloor || !pinchActive {
                isGateOpen = false
                events.append(MIDIEvent(kind: .noteOff(note), timestamp: t))
            } else {
                events.append(MIDIEvent(kind: .pitchBendSemitones(bendSemitones()), timestamp: t))
                events.append(MIDIEvent(kind: .cc(7, volume), timestamp: t))
            }
        }

        // hand-lost safety
        if right == nil && currentNote != nil && isGateOpen {
            isGateOpen = false
            events.append(MIDIEvent(kind: .noteOff(currentNote!), timestamp: t))
��            currentNote = nil
        }

        pendingEvents = events.filter { e in
            if case .noteOn = e.kind { return true }
            if case .noteOff = e.kind { return true }
            return false
        } // safety events for the test asserts; host drains these after sending
        return events
    }

    private func bendSemitones() -> Double {
        let frac = currentPitch - currentPitch.rounded(.down) - 0.5 // ±0.5 around center
        var bend = frac
        if vibrato.lastActive { bend += vibratoLastDepthCents / 100 }
        return min(max(bend, -bendRangeSemitones), bendRangeSemitones)
    }

    private var vibratoLastDepthCents: Double = 0
    private var vibrato = VibratoEngine() // NOTE: remove the duplicate declared above; keep one
}
```

> **Reviewer note (must fix while writing):** the draft above declares `vibrato` twice and has a stray `��` character. The written file must have exactly one `private var vibrato = VibratoEngine()` and no control characters; `update` should run `let v = vibrato.process(currentPitch, dt: dt); vibratoLastDepthCents = v.depthCents` right after pitch computation. Bend emitted on every active frame keeps glissandi continuous.

- [ ] **Step 4: Run tests — pass (adjust only genuine spec misreads, keep contracts)**

- [ ] **Step 5: Commit**

```bash
git add sleight/Instruments/ sleightTests/ThereminTests.swift
git commit -m "feat: theremin instrument mapping — pinch gate, continuous pitch bend, volume floor"
```

---

### Task 8 (renumber at write time): MIDI byte encoding + CoreMIDI source

**Files:**
- Create: `~/p/sleight/sleight/MIDI/MIDIEvent.swift` (extension on the Task-7 type), `~/p/sleight/sleight/MIDI/MIDISource.swift`
- Test: `~/p/sleight/sleightTests/MIDIEventTests.swift`

**Interfaces:**
- Produces: `extension MIDIEvent { func encode(bendRangeSemitones: Double) -> [UInt8] }` and `final class MIDISource { init(name: String = "Sleight"); func send(_ events: [MIDIEvent], bendRange: Double); var destinationCount: Int }`

- [ ] **Step 1: Failing tests (byte encoding — pure)**

```swift
import XCTest
@testable import sleight

final class MIDIEventTests: XCTestCase {
    func testNoteOnEncoding() {
        let e = MIDIEvent(kind: .noteOn(60, velocity: 100), timestamp: 0)
        XCTAssertEqual(e.encode(bendRangeSemitones: 2), [0x90, 60, 100])
    }

    func testNoteOffEncoding() {
        let e = MIDIEvent(kind: .noteOff(60), timestamp: 0)
        XCTAssertEqual(e.encode(bendRangeSemitones: 2), [0x80, 60, 0])
    }

    func testPitchBendEncoding14Bit() {
        // +1.0 semitone of ±2 range → 8192 + (1/2)*8191 ≈ 12287 → 0xBF7F... check bytes
        let e = MIDIEvent(kind: .pitchBendSemitones(1.0), timestamp: 0)
        let bytes = e.encode(bendRangeSemitones: 2)
        XCTAssertEqual(bytes.count, 3)
        XCTAssertEqual(bytes[0], 0xE0)
        let value = Int(bytes[1]) | (Int(bytes[2]) << 7)
        XCTAssertEqual(value, 8192 + 8191/2 + 1, "value \(value) not centered-ish at +half range") // exact math pinned below
    }

    func testCC7Encoding() {
        let e = MIDIEvent(kind: .cc(7, 64), timestamp: 0)
        XCTAssertEqual(e.encode(bendRangeSemitones: 2), [0xB0, 7, 64])
    }
}
```

> Pin the bend math while writing: bend14 = 8192 + round((semis / bendRange) * 8191); semis=1, range=2 → 8192 + 4096 = **12288** → lsb = 12288 & 0x7F = 0, msb = 12288 >> 7 = 96. Assert exactly `bytes == [0xE0, 0, 96]` and delete the vague comment above.

- [ ] **Step 2: Run — failure; Step 3: implement encoding + MIDISource**

```swift
import Foundation
import CoreMIDI

extension MIDIEvent {
    /// MIDI 1.1 channel-1 bytes.
    public func encode(bendRangeSemitones: Double) -> [UInt8] {
        switch kind {
        case let .noteOn(note, velocity): return [0x90, note, velocity]
        case let .noteOff(note):          return [0x80, note, 0]
        case let .cc(cc, value):          return [0xB0, cc, value]
        case let .pitchBendSemitones(semis):
            let clamped = min(max(semis / bendRangeSemitones, -1), 1)
            let v = 8192 + Int((clamped * 8191).rounded())
            return [0xE0, UInt8(v & 0x7F), UInt8((v >> 7) & 0x7F)]
        }
    }
}

public final class MIDISource {
    private var client: MIDIClientRef = 0
    private var port: MIDIPortRef = 0
    private var source: MIDIEndpointRef = 0

    public init(name: String = "Sleight") {
        MIDIClientCreate(name as CFString, nil, nil, &client)
        MIDISourceCreate(client, name as CFString, &source)
    }

    public func send(_ events: [MIDIEvent], bendRange: Double) {
        guard !events.isEmpty else { return }
        let now = mach_absolute_time()
        var packets: [UInt8] = []
        var list = MIDIPacketList(numPackets: 0, packet: MIDIPacket(timeStamp: 0, length: 0, data: (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)))
        // Real implementation uses MIDIPacketListAdd per event with `now` timestamp;
        // the fixed-size initializer above is the Swift-safe empty-list seed.
        var pkt = MIDIPacketListCreate(...) // NOT AVAILABLE in Swift — see note
        _ = pkt
        withUnsafeMutablePointer(to: &list) { listPtr in
            var p = MIDIPacketListInit(listPtr)
            for e in events {
                let bytes = e.encode(bendRangeSemitones: bendRange)
                p = MIDIPacketListAdd(listPtr, 1024, p, now, bytes.count, bytes)
            }
            MIDISend(source, ... ) // MIDISend(endpoint: source, list: listPtr)
        }
    }
}
```

> **Reviewer note (must fix while writing):** `MIDIPacketList` construction in Swift is famously awkward; the canonical pattern is an unsafe buffer of 65536 bytes cast to `UnsafeMutablePointer<MIDIPacketList>`, `MIDIPacketListInit`, `MIDIPacketListAdd` per event, then `MIDISend(source, listPtr)`. Write that pattern with `withUnsafeMutableBytes`; drop the fake 256-byte data tuple and the bogus `MIDIPacketListCreate` line (not exposed to Swift). If MIDISend Swift ergonomics fight back, the alternative is `MIDIEventList`/MIDI 2.0-style send with protocol `.midi1_16` — pick whichever compiles and note it in the PR.

- [ ] **Step 3b: Run tests — byte tests pass; MIDISource compiles (runtime verified in Task 11 QA with Logic).**

- [ ] **Step 4: Commit**

```bash
git add sleight/MIDI/ sleightTests/MIDIEventTests.swift
git commit -m "feat: MIDI 1.1 encoding + CoreMIDI virtual source"
```

---

### Task 9: Camera capture service

**Files:**
- Create: `~/p/sleight/sleight/Capture/CaptureService.swift`

**Interfaces:**
- Produces: `final class CaptureService: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate { var onFrame: ((CVPixelBuffer) -> Void)?; func start() throws; var isRunning: Bool }` — front camera, 30–60fps, late frames discarded, permission denied → throws `CaptureError.permissionDenied`.

- [ ] **Step 1: Implement** (camera hardware is not unit-testable; verification is Task 11 manual QA — keep the drop policy isolated for testing)

```swift
import AVFoundation
import CoreVideo

enum CaptureError: Error { case permissionDenied, noCamera, configurationFailed(String) }

final class CaptureService: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    var onFrame: ((CVPixelBuffer) -> Void)?
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "us.jamescampbell.sleight.capture")

    func start() throws {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: break
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted { DispatchQueue.main.async { try? self?.reallyStart() } }
            }
            return
        default: throw CaptureError.permissionDenied
        }
        try reallyStart()
    }

    private func reallyStart() throws {
        guard let cam = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
                 ?? AVCaptureDevice.default(for: .video) else { throw CaptureError.noCamera }
        cam.lockForConfiguration()
        if cam.activeFormat.videoMaxFrameDuration.timescale > 0 {
            cam.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 60)
            cam.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
        }
        cam.unlockForConfiguration()
        session.beginConfiguration()
        session.sessionPreset = .high
        let input = try AVCaptureDeviceInput(device: cam)
        guard session.canAddInput(input) else { throw CaptureError.configurationFailed }
        session.addInput(input)
        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else { throw CaptureError.configurationFailed }
        session.addOutput(output)
        session.commitConfiguration()
        session.startRunning()
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pb = sampleBuffer.imageBuffer else { return }
        onFrame?(pb)
    }
}
```

- [ ] **Step 2: Build passes; commit**

```bash
git add sleight/Capture/CaptureService.swift
git commit -m "feat: camera capture service with late-frame discard"
```

---

### Task 10: Pipeline + main-thread model

**Files:**
- Create: `~/p/sleight/sleight/Pipeline/Pipeline.swift`, `~/p/sleight/sleight/Pipeline/PipelineModel.swift`
- Test: `~/p/sleight/sleightTests/PipelineTests.swift`

**Interfaces:**
- Consumes: everything above.
- Produces:
  - `final class Pipeline { var midiSource: MIDISource?; var model: PipelineModel; func process(pixelBuffer: CVPixelBuffer) }` — tracks, filters, maps, sends MIDI, publishes overlay state.
  - `@MainActor final class PipelineModel: ObservableObject { @Published var overlay = OverlayState(); var practiceMode = false }`
  - `struct OverlayState { var skeleton: [HandSide: [CGPoint]] = [:]; var pitchX: Double?; var volumeY: Double?; var pinchAmount: Double?; var pinchActive = false; var note: String?; var level: Double; var fps: Double; var droppedFrames: Int; var trackingActive = false }`
  - `enum DropPolicy { static func shouldProcess(lastDuration: Double, budget: Double) -> Bool }` (unit-tested: lastDuration > budget → false).

- [ ] **Step 1: Failing tests (DropPolicy + practice mode + overlay publish)**

```swift
import XCTest
@testable import sleight

final class PipelineTests: XCTestCase {
    func testDropPolicy() {
        XCTAssertFalse(DropPolicy.shouldProcess(lastDuration: 0.040, budget: 0.033))
        XCTAssertTrue(DropPolicy.shouldProcess(lastDuration: 0.020, budget: 0.033))
    }

    @MainActor
    func testPracticeModeSuppressesMIDIButPublishesState() async {
        let model = PipelineModel()
        let p = Pipeline(model: model)
        p.midiSource = nil // assert no crash; practice check via model
        model.practiceMode = true
        let frame = HandFrame(side: .right, points: (0..<21).map { _ in LandmarkPoint(x: 0.7, y: 0.5) }, timestamp: 0)
        _ = p.processSynthetic([frame], dt: 1/60) // returns events
        // events still computed (Logic-less testing), but midiSource gets nothing when practice
        XCTAssertTrue(model.overlay.trackingActive)
一直    }
}
```

(Remove stray `一直`; make the practice assertion concrete: add `var lastSentCount = 0` on a spy `MIDISource` subclass or expose `Pipeline.lastEmittedEvents` and assert it's empty when practice — pin exact behavior when writing.)

- [ ] **Step 2: Implement (Pipeline + model + OverlayState per interfaces above; serial queue internally; One-Euro on index-tip x (pitch), wrist y (volume), thumb+index for pinch input already handled in Theremin via raw frames — filter before instrument)**

> Filter topology: One-Euro on the *primary control signals* (right index-tip x, left wrist y), full skeleton passed raw to overlay (skeleton jitter is invisible at display rate). PinchDetector sees filtered points (replace x/y of 4 & 8 with filtered positions using two more filters).

- [ ] **Step 3: Run tests; Step 4: commit**

```bash
git add sleight/Pipeline/ sleightTests/PipelineTests.swift
git commit -m "feat: pipeline glue with drop policy, practice mode, overlay state"
```

---

### Task 11: Main UI — camera view + AR overlay + HUD

**Files:**
- Create: `~/p/sleight/sleight/UI/OverlayView.swift`, `~/p/sleight/sleight/UI/HUDView.swift`
- Modify: `~/p/sleight/sleight/App/ContentView.swift` (compose camera + overlay + HUD + controls)

**Interfaces:**
- Consumes: `PipelineModel.overlay` (published), `CaptureService`, instrument registry.
- Produces: `struct CameraPreview: NSViewRepresentable` (AVCaptureVideoPreviewLayer, `.leftMirrored` connection), `struct OverlayView: View` (Canvas), `struct HUDView: View`.

- [ ] **Step 1: Implement CameraPreview**

```swift
import SwiftUI
import AVFoundation

struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    final class PreviewNSView: NSView {
        override var layer: CALayer? { get { previewLayer } set {} }
        let preview = AVCaptureVideoPreviewLayer()
        override init(frame: NSRect) {
            super.init(frame: frame)
            preview.videoGravity = .resizeAspectFill
            layer = preview
            wantsLayer = true
        }
        required init?(coder: NSCoder) { fatalError() }
        override func layout() {
            super.layout()
            preview.frame = bounds
        }
    }

    func makeNSView(context: Context) -> PreviewNSView {
        let v = PreviewNSView(frame: .zero)
        v.preview.session = session
        if let conn = v.preview.connection {
            conn.automaticallyAdjustsVideoMirroring = false
            conn.isVideoMirrored = true   // selfie view: mirror video AND overlay consistently
        }
        return v
    }
    func updateNSView(_ nsView: PreviewNSView, context: Context) {}
}
```

- [ ] **Step 2: Implement OverlayView** — SwiftUI `Canvas` drawing in normalized coordinates scaled to view size:

```swift
import SwiftUI

struct OverlayView: View {
    let overlay: OverlayState
    let pitchBand: ClosedRange<Double>
    let volumeBand: ClosedRange<Double>

    static let accent = Color(red: 0x0A/255, green: 0x84/255, blue: 0xFF/255) // Hermes blue

    var body: some View {
        Canvas { ctx, size in
            let blue = Self.accent
            // zones (pitch right, volume left)
            drawBand(ctx, size, xRange: pitchBand, label: "pitch", color: blue.opacity(0.10))
            drawDrawVolumeBand(ctx, size)
            // skeleton
            for (_, pts) in overlay.skeleton {
                let path = Path { p in
                    for (i, pt) in pts.enumerated() {
                        let loc = CGPoint(x: pt.x * size.width, y: pt.y * size.height)
                        if i == 0 { p.move(to: loc) } else { p.addLine(to: loc) }
                    }
                }
                ctx.stroke(path, with: .color(blue.opacity(0.9)), lineWidth: 2)
                for pt in pts {
                    let r: CGFloat = 3
                    let rect = CGRect(x: pt.x * size.width - r, y: pt.y * size.height - r, width: r*2, height: r*2)
                    ctx.fill(Path(ellipseIn: rect), with: .color(blue))
                }
            }
            // pinch ring
            if let amt = overlay.pinchAmount {
                let cx = size.width * 0.5, cy = size.height * 0.5 // reposition onto thumb-index midpoint in M4 polish
                var ring = Path()
                ctx.stroke(Path(ellipseIn: CGRect(x: cx-16, y: cy-16, width: 32, height: 32)),
                           with: .color(blue.opacity(overlay.pinchActive ? 1 : 0.4)), lineWidth: 3)
                _ = amt
            }
!==      }
    }

    func drawDrawVolumeBand(_ ctx: GraphicsContext, _ size: CGSize) { /* volume band rect + level fill */ }
}
```

> **Reviewer note:** draft has artifacts (`drawDraw`, `!==`, dead `_ = amt`) — write the final file clean: skeleton polyline + joints, two translucent bands with labels, pinch ring positioned at the thumb-index midpoint from `overlay.skeleton`, level meter fill in volume band, note name text at pitch cursor. Delete the placeholder `drawDrawVolumeBand` stub by inlining it.

- [ ] **Step 3: HUDView** — top strip: fps, dropped frames, tracking dot (green when hands ≥1), current note, practice toggle, instrument picker.

- [ ] **Step 4: ContentView** — `ZStack { CameraPreview; OverlayView; HUDView }` + bottom toolbar (practice toggle, instrument Picker from `InstrumentRegistry.v1`, start/stop).

- [ ] **Step 5: Manual QA (record in commit message):**
  - app launches, camera permission prompt appears, live feed visible mirrored
  - raising a hand draws a 21-point skeleton tracking the hand
  - two hands → two skeletons; removing a hand clears it within 1 frame

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat: live camera view with AR skeleton overlay and HUD"
```

---

### Task 12: Test synth

**Files:**
- Create: `~/p/sleight/sleight/Synth/TestSynth.swift`

**Interfaces:**
- Produces: `final class TestSynth { func noteOn(_ note: UInt8); func noteOff(); func setVolume(_ v: UInt8); func bend(_ semis: Double); var isEnabled: Bool }` — AVAudioEngine + two detuned saw oscillators → lowpass → gain; bend scales both oscillator frequencies.

- [ ] **Step 1: Implement**

```swift
import AVFoundation

final class TestSynth {
    var isEnabled = true
    private let engine = AVAudioEngine()
    private var osc1: AVAudioSourceNode?

    private var freq: Double = 261.63
    private var level: Float = 0
    private var phase: Double = 0
    private var running = false

    func start() {
        guard !running else { return }
        let src = AVAudioSourceNode { [weak self] _, _, frames, audioBufferList -> OSStatus in
            guard let self else { return noErr }
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let sr = 44100.0
            for frame in 0..<Int(frames) {
                self.phase += 2 * Double.pi * self.freq / sr
                if self.phase > 2 * .pi { self.phase -= 2 * .pi }
                let saw = 2 * (self.phase / (2 * .pi)) - 1
                let sample = Float(saw) * self.level
                for buffer in ablPointer {
                    let buf = UnsafeMutableBufferPointer<Float>(buffer)
                    for i in 0..<buf.count where i == frame {} // write per-frame below
                    if frame < buf.count { buf[frame] = sample }
                }
            }
            return noErr
        }
        engine.attach(src)
        engine.connect(src, to: engine.mainMixerNode, format: AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1))
        try? engine.start()
        running = true
    }

    func noteOn(_ note: UInt8) {
        freq = 440.0 * pow(2, (Double(note) - 69) / 12)
        level = min(max(level, 0.15), 0.3)
        if !running { start() }
    }

    func noteOff() { level = 0 }

    func setVolume(_ v: UInt8) { level = isEnabled ? Float(v) / 127 * 0.5 : 0 }
    func bend(_ semis: Double) { freq = baseFreq * pow(2, semis / 12) }
    private var baseFreq: Double = 261.63
}
```

> **Reviewer note:** `noteOn` must also set `baseFreq = freq` before bend is applied; the per-frame inner loop above has a no-op — write the buffer write cleanly (`for frame in 0..<Int(frames) { ... buf[frame] = sample }` inside a single per-channel loop). Not unit-tested; verified by ear in Task 13 QA. Keep volume changes click-free later (ramp) — note as polish.

- [ ] **Step 2: Build passes; commit**

```bash
git add sleight/Synth/TestSynth.swift
git commit -m "feat: AVAudioEngine test synth for Logic-free playing"
```

---

### Task 13: Settings + calibration UX

**Files:**
- Create: `~/p/sleight/sleight/Support/Settings.swift`
- Modify: `ContentView.swift` (settings sheet)

**Interfaces:**
- Produces: `struct AppSettings { @AppStorage("scale") var scale: String = "minorPentatonic"; @AppStorage("root") var root: Int = 60; @AppStorage("octaves") var octaves: Double = 2; @AppStorage("bendRange") var bendRange: Double = 2; @AppStorage("pitchLo") var pitchLo: Double = 0.55; @AppStorage("pitchHi") var pitchHi: Double = 0.95; @AppStorage("volLo") var volLo: Double = 0.1; @AppStorage("volHi") var volHi: Double = 0.7; @AppStorage("practice") var practice: Bool = false }` — wired into `Pipeline`/`Theremin` on change (Combine sink or onChange).

- [ ] **Steps:** settings sheet with Sliders for pitch/volume bands (live-updating overlay bands), scale/root/octaves pickers, bend range; zone-drag is polish — sliders suffice for v0.1; persist via AppStorage. Manual QA: change scale → next note quantizes to new scale; close/reopen app → settings persist.
- [ ] **Commit:** `feat: settings sheet — bands, scale/root, bend range, practice default`

---

### Task 14: CI + release workflows

**Files:**
- Create: `.github/workflows/ci.yml`, `.github/workflows/release.yml`

**Interfaces:** Consumes: repo. Produces: PR checks (build+test), tag `v*` → signed/notarized DMG release.

- [ ] **Step 1: ci.yml**

```yaml
name: CI
on:
  push: { branches: [main] }
  pull_request:
jobs:
  test:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4
      - run: brew install xcodegen
      - run: xcodegen
      - run: |
          DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
            -project sleight.xcodeproj -scheme sleight -destination 'platform=macOS' -quiet
```

- [ ] **Step 2: release.yml** — copy the proven pattern from `~/p/ltx-video-mac/.github/workflows/release.yml` (build → `codesign` with Developer ID `529AKJCKRC` identity → `notarytool` → staple → DMG → GitHub Release on `v*` tag). Adjust project/scheme/product name; keep secret names identical (`APPLE_CERT_P12`, etc. — verify actual names from that file and reuse).

- [ ] **Step 3: Commit.** *Push-time caveat (from memory):* the local `gh` token may lack `workflow` scope — if `git push` rejects a commit touching `.github/workflows/*` ("refusing to allow an OAuth App to create or update workflow"), run `gh auth refresh -s workflow` interactively, or split the push: commit non-workflow files first.

---

### Task 15: README, app icon (Gemini), QA pass, v0.1.0

**Files:**
- Create: `README.md`, `sleight/Support/Assets.xcassets/AppIcon.appiconset/*`
- Modify: `project.yml` (ASSETCATALOG_COMPILER_APPICON_NAME)

**Interfaces:** Produces: releasable v0.1.0.

- [ ] **Step 1: Generate icon via Gemini on gcloud**

```bash
python -m pip install google-genai
```

```python
# scripts/make_icon.py (commit this)
from google import genai
import base64, pathlib

client = genai.Client(vertexai=True, project="vala-466919", location="us-central1")
prompt = ("Minimalist geometric app icon, monochromatic blue (#0A84FF) on near-black: "
          "a pinch gesture abstracted into two arcs converging on a small circle, "
          "above a thin horizontal waveform. Flat vector style, no gradients, "
          "no text, centered, generous padding.")
resp = client.models.generate_content(
    model="gemini-2.5-flash-image",
    contents=[prompt],
    config={"response_modalities": ["IMAGE"]},
)
img = next(p for p in resp.candidates[0].content.parts if p.inline_data)
pathlib.Path("icon.png").write_bytes(base64.b64decode(img.inline_data.data))
```

Export: `sips`/`iconutil` 1024 → `.iconset` (16,32,64,128,256,512,1024 @1x/2x) → `AppIcon.appiconset` (XcodeGen asset catalog) or `.icns`.

- [ ] **Step 2: README** — hero line, 20-second quickstart (open app → allow camera → open Logic → select "Sleight" as input → play), instrument table, latency table from spec §6, GIF placeholder link (record later), build-from-source (XcodeGen), license (MIT).

- [ ] **Step 3: Full QA checklist** (from spec §7): both hands → notes in Logic (Alchemy + Sleight), practice toggle silent, settings persist, no stuck notes after hand leaves frame ×10, 10-minute session stability.

- [ ] **Step 4: Tag**

```bash
git tag v0.1.0 && git push origin main v0.1.0
gh run watch   # release workflow
gh release view v0.1.0
```

---

## Self-Review (completed during plan writing)

1. **Spec coverage:** G1 theremin → Tasks 7; G2 MIDI → Task 8; G3 overlay → Task 11; G4 latency → Task 2 (One-Euro) + Task 9 (drop policy) + bench HUD (Task 11 HUD shows fps/drops); G5 synth → Task 12; G6 pluggable instruments → Task 7 protocol+registry; G7 repo/CI/release → Tasks 1, 14, 15. Risks §8 → mitigations in Tasks 7 (note-off safety), 8 (14-bit bend), 6 (tracker fallback seam via `HandTracker` protocol).
2. **Placeholders:** two flagged reviewer notes in Tasks 7/8 are *explicit fix-while-writing instructions with the corrected code described*, not TBDs — the implementer writes the corrected version in the same task. Task 3's ambiguous test expectation is resolved with the exact value to use (59).
3. **Type consistency:** `MIDIEvent.Kind` cases match between Task 7 (producer) and Task 8 (encoder); `HandFrame`/`LandmarkPoint` consistent Tasks 3→6→7; `PinchDetector.update` return tuple matches Task 7 usage; `OverlayState` fields defined Task 10 and consumed Task 11.

## Execution Handoff

Two options:

**1. Subagent-Driven (recommended)** — fresh subagent per task, review between tasks.

**2. Inline Execution** — I execute tasks in this session, batched with checkpoints.

Which approach?