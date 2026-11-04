import CoreMotion
import Foundation

/// Streams AirPods head orientation (via CMHeadphoneMotionManager) and reports
/// frame-to-frame rotation deltas in degrees.
///
/// Sign convention of the reported deltas:
///   dYaw   > 0  → head turned LEFT
///   dPitch > 0  → head tilted UP
final class HeadMotionController: NSObject, CMHeadphoneMotionManagerDelegate {
    private let manager = CMHeadphoneMotionManager()

    /// (dYawDegrees, dPitchDegrees, dtSeconds)
    var onDelta: ((Double, Double, Double) -> Void)?
    var onConnectionChange: ((Bool) -> Void)?
    var onError: ((String) -> Void)?
    /// A possible earbud tap started (cursor movement is frozen meanwhile).
    var onTapCandidate: (() -> Void)?
    /// An earbud tap was confirmed.
    var onEarbudTap: (() -> Void)?

    let tapDetector = EarbudTapDetector()
    /// Cursor movement is ignored until this time (while a tap is being checked
    /// and just after it, so the jolt of tapping doesn't move the cursor).
    private var suppressMovementUntil: TimeInterval = 0

    private var lastYaw: Double?
    private var lastPitch: Double?
    private var lastTimestamp: TimeInterval?

    var authorizationDescription: String {
        switch CMHeadphoneMotionManager.authorizationStatus() {
        case .authorized: return "authorized"
        case .denied: return "denied"
        case .restricted: return "restricted"
        case .notDetermined: return "not determined"
        @unknown default: return "unknown"
        }
    }

    func start() {
        guard manager.isDeviceMotionAvailable else {
            onError?("Headphone motion is not available on this Mac.")
            return
        }
        manager.delegate = self
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            guard let self else { return }
            if let error {
                self.onError?("Motion error: \(error.localizedDescription)")
                return
            }
            guard let motion else { return }
            self.handle(motion)
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        resetReference()
    }

    /// Forget the last sample so the next one doesn't produce a jump.
    func resetReference() {
        tapDetector.reset()
        lastYaw = nil
        lastPitch = nil
        lastTimestamp = nil
    }

    private func handle(_ motion: CMDeviceMotion) {
        let yaw = motion.attitude.yaw
        let pitch = motion.attitude.pitch
        let t = motion.timestamp
        defer {
            lastYaw = yaw
            lastPitch = pitch
            lastTimestamp = t
        }
        guard let ly = lastYaw, let lp = lastPitch, let lt = lastTimestamp else { return }

        let dt = t - lt
        // Ignore stale gaps (e.g. AirPods were taken out and put back in).
        guard dt > 0, dt < 0.5 else { return }

        let a = motion.userAcceleration
        let magnitude = (a.x * a.x + a.y * a.y + a.z * a.z).squareRoot()
        if magnitude > 0.15 {
            DebugLog.write(String(format: "accel peak %.2f g (tap threshold %.2f g)", magnitude, tapDetector.threshold))
        }

        switch tapDetector.process(magnitude: magnitude, timestamp: t) {
        case .candidate:
            suppressMovementUntil = t + 0.35
            onTapCandidate?()
            return
        case .confirmed:
            DebugLog.write("earbud tap detected")
            onEarbudTap?()
            return
        case .rejected:
            suppressMovementUntil = 0
        case .none:
            if t < suppressMovementUntil { return }
        }

        let dYaw = Self.wrap(yaw - ly) * 180 / .pi
        let dPitch = Self.wrap(pitch - lp) * 180 / .pi
        onDelta?(dYaw, dPitch, dt)
    }

    /// Wrap an angle difference into (-π, π] so crossing ±180° doesn't explode.
    private static func wrap(_ a: Double) -> Double {
        atan2(sin(a), cos(a))
    }

    // MARK: CMHeadphoneMotionManagerDelegate

    func headphoneMotionManagerDidConnect(_ manager: CMHeadphoneMotionManager) {
        resetReference()
        DispatchQueue.main.async { self.onConnectionChange?(true) }
    }

    func headphoneMotionManagerDidDisconnect(_ manager: CMHeadphoneMotionManager) {
        resetReference()
        DispatchQueue.main.async { self.onConnectionChange?(false) }
    }
}
