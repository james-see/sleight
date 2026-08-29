import Foundation
import CoreVideo
import SwiftUI

/// Display-rate overlay state, published to SwiftUI from the main thread.
struct OverlayState {
    var skeleton: [HandSide: [CGPoint]] = [:]
    var pitchX: Double?            // right-hand normalized position (nil = no hand)
    var volumeY: Double?           // left-hand normalized level 0…1
    var pinchAmount: Double?
    var pinchActive = false
    var noteName: String?
    var level: Double = 0          // 0…1
    var fps: Double = 0
    var droppedFrames: Int = 0
    var trackingActive = false
    var vibratoActive = false
}

enum DropPolicy {
    /// Stale frames are useless for a real-time instrument — skip if the last
    /// frame overran its budget. Self-recovering: the frame right after a drop
    /// is always processed, so one slow frame costs one drop (never a wedge)
    /// and sustained overload degrades to half rate instead of freezing.
    static func shouldProcess(lastDuration: Double, budget: Double, justDropped: Bool) -> Bool {
        justDropped || lastDuration <= budget
    }
}

@MainActor
final class PipelineModel: ObservableObject {
    @Published var overlay = OverlayState()
}

/// Reference box so per-frame filter state mutates in place.
final class FilterBox {
    var filter: OneEuroFilter
    init(minCutoff: Double, beta: Double, dCutoff: Double) {
        self.filter = OneEuroFilter(minCutoff: minCutoff, beta: beta, dCutoff: dCutoff)
    }
}

/// Glues capture → track → filter → map → output. Runs its work on the capture
/// queue; publishes UI state to the main thread; never queues frames.
final class Pipeline {
    let model: PipelineModel
    var midiSource: MIDISource?
    var instrument: any Instrument
    /// Mirror of the UI practice toggle (plain flag: read from the capture queue).
    var practiceMode = false
    /// Observer hook (test synth listens here).
    var onEvents: (([MIDIEvent]) -> Void)?

    private let tracker: HandTracker
    private var filters: [HandSide: [String: FilterBox]] = [:]
    private var frameBudget: Double = 1.0 / 30.0
    private var lastDuration: Double = 0
    private var fpsCounter = 0
    private var fpsWindowStart = DispatchTime.now()
    private var lastFps: Double = 0
    private var droppedFrames = 0
    private var justDropped = false

    init(model: PipelineModel, tracker: HandTracker = VisionHandTracker(), instrument: any Instrument = Theremin()) {
        self.model = model
        self.tracker = tracker
        self.instrument = instrument
        self.midiSource = MIDISource.shared
    }

    /// Entry point from CaptureService (capture queue context).
    func process(pixelBuffer: CVPixelBuffer) {
        let start = DispatchTime.now()
        guard DropPolicy.shouldProcess(lastDuration: lastDuration, budget: frameBudget, justDropped: justDropped) else {
            droppedFrames += 1
            justDropped = true
            return
        }
        justDropped = false

        let t = Double(start.uptimeNanoseconds) / 1e9
        let dt = lastDuration == 0 ? 1.0 / 60 : lastDuration
        let hands = tracker.detect(pixelBuffer, at: t)
        let filtered = filter(hands, dt: dt)
        let events = instrument.update(hands: filtered, dt: dt)

        if !practiceMode {
            midiSource?.send(events)
        }
        onEvents?(events)

        publish(hands: filtered)
        lastDuration = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1e9
    }

    /// Testable core: given hand frames, produce events and publish state.
    /// Called from MainActor contexts (tests) — publishes synchronously.
    func processSynthetic(_ hands: [HandFrame], dt: Double) -> [MIDIEvent] {
        let filtered = filter(hands, dt: dt)
        let events = instrument.update(hands: filtered, dt: dt)
        publish(hands: filtered, synchronous: true)
        return events
    }

    /// One-Euro the primary control signals (index-tip x, wrist y) per hand;
    /// skeleton goes to the overlay raw (jitter invisible at display rate).
    private func filter(_ hands: [HandFrame], dt: Double) -> [HandFrame] {
        hands.map { hand in
            var pts = hand.points
            pts[Landmark.indexTip].x = box(hand.side, key: "pitchX").filter.filter(pts[Landmark.indexTip].x, dt: dt)
            pts[Landmark.indexTip].y = box(hand.side, key: "pitchY").filter.filter(pts[Landmark.indexTip].y, dt: dt)
            pts[Landmark.wrist].x = box(hand.side, key: "volumeX").filter.filter(pts[Landmark.wrist].x, dt: dt)
            pts[Landmark.wrist].y = box(hand.side, key: "volumeY").filter.filter(pts[Landmark.wrist].y, dt: dt)
            return HandFrame(side: hand.side, points: pts, timestamp: hand.timestamp)
        }
    }

    private func box(_ side: HandSide, key: String) -> FilterBox {
        if let b = filters[side]?[key] { return b }
        let b = FilterBox(minCutoff: 1.2, beta: 0.02, dCutoff: 1.0)
        filters[side, default: [:]][key] = b
        return b
    }

    private func publish(hands: [HandFrame], synchronous: Bool = false) {
        let inst = instrument
        var skel: [HandSide: [CGPoint]] = [:]
        for h in hands {
            skel[h.side] = h.points.map { CGPoint(x: $0.x, y: $0.y) }
        }
        let right = hands.first { $0.side == .right }
        let left = hands.first { $0.side == .left }
        let pitchX: Double? = right.map { h in
            min(max((h.points[Landmark.indexTip].x - inst.pitchBand.lowerBound) /
                    (inst.pitchBand.upperBound - inst.pitchBand.lowerBound), 0), 1)
        }
        let volY: Double? = left.map { h in
            min(max(1 - (h.points[Landmark.wrist].y - inst.volumeBand.lowerBound) /
                    (inst.volumeBand.upperBound - inst.volumeBand.lowerBound), 0), 1)
        }
        fpsCounter += 1
        let now = DispatchTime.now()
        let window = Double(now.uptimeNanoseconds - fpsWindowStart.uptimeNanoseconds) / 1e9
        var fps = lastFps
        if window > 0.5 {
            fps = Double(fpsCounter) / window
            lastFps = fps
            fpsCounter = 0
            fpsWindowStart = now
        }

        let state = OverlayState(
            skeleton: skel,
            pitchX: pitchX,
            volumeY: volY,
            pinchAmount: hands.isEmpty ? nil : inst.lastPinchAmount,
            pinchActive: inst.isGateOpen,
            noteName: inst.isGateOpen ? MusicTheory.noteName(Int(inst.currentPitch.rounded())) : nil,
            level: Double(inst.lastVolume) / 127.0,
            fps: fps,
            droppedFrames: droppedFrames,
            trackingActive: !hands.isEmpty,
            vibratoActive: inst.vibratoActive
        )
        if synchronous {
            MainActor.assumeIsolated {
                model.overlay = state
            }
        } else {
            Task { @MainActor in
                model.overlay = state
            }
        }
    }
}