import Foundation

/// Detects a physical tap on an earbud from the AirPods accelerometer stream.
///
/// A tap shows up as a short, sharp spike in user acceleration. Head movement
/// also produces acceleration, but it builds up gradually and lasts across
/// several samples. So a tap must:
///   1. jump above `threshold` from a calm previous sample (sudden onset), and
///   2. fall back down on the very next sample (short duration).
/// Waiting one sample (~40 ms at 25 Hz) for step 2 removes most false positives.
final class EarbudTapDetector {
    enum Result {
        case none
        /// A spike started; it might be a tap. Freeze the cursor until we know.
        case candidate
        /// The spike was short: it was a tap.
        case confirmed
        /// The spike lasted: it was head movement, not a tap.
        case rejected
    }

    /// Spike size in g (1 g = 9.81 m/s²) needed to count as a tap.
    var threshold = 0.5

    private var previousMagnitude = 0.0
    private var candidateTime: TimeInterval?
    private var lastTapTime: TimeInterval = -.infinity

    /// Minimum gap between taps, so one tap's ringing isn't counted twice.
    private let refractory: TimeInterval = 0.12

    func process(magnitude: Double, timestamp: TimeInterval) -> Result {
        defer { previousMagnitude = magnitude }

        if candidateTime != nil {
            candidateTime = nil
            if magnitude < threshold * 0.6 {
                lastTapTime = timestamp
                return .confirmed
            }
            return .rejected
        }

        let calmBefore = previousMagnitude < threshold * 0.5
        let outOfRefractory = timestamp - lastTapTime > refractory
        if magnitude > threshold, calmBefore, outOfRefractory {
            candidateTime = timestamp
            return .candidate
        }
        return .none
    }

    func reset() {
        previousMagnitude = 0
        candidateTime = nil
    }
}
