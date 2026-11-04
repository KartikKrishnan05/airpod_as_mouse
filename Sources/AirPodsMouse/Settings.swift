import Foundation

/// Something the user can do with their AirPods.
enum Gesture: String, CaseIterable {
    case stemSingle, stemDouble, stemTriple
    case earbudTap, earbudDoubleTap
    case caseLid

    var title: String {
        switch self {
        case .stemSingle: return "Stem Press ×1"
        case .stemDouble: return "Stem Press ×2"
        case .stemTriple: return "Stem Press ×3"
        case .earbudTap: return "Earbud Tap"
        case .earbudDoubleTap: return "Earbud Double Tap"
        case .caseLid: return "Case Lid Open/Close"
        }
    }

    var defaultAction: GestureAction {
        switch self {
        case .stemSingle: return .leftClick
        case .stemDouble: return .rightClick
        case .stemTriple: return .toggleTracking
        case .earbudTap: return .leftClick
        case .earbudDoubleTap: return .none
        case .caseLid: return .leftClick
        }
    }
}

/// What a gesture does.
enum GestureAction: String, CaseIterable {
    case none, leftClick, rightClick, middleClick, doubleClick, toggleTracking

    var title: String {
        switch self {
        case .none: return "Do Nothing"
        case .leftClick: return "Left Click"
        case .rightClick: return "Right Click"
        case .middleClick: return "Middle Click"
        case .doubleClick: return "Double Click"
        case .toggleTracking: return "Pause / Resume Tracking"
        }
    }
}

/// User-tunable settings, persisted in UserDefaults.
final class Settings {
    static let shared = Settings()
    private let defaults = UserDefaults.standard

    /// Pixels of cursor travel per degree of head rotation (before acceleration).
    var sensitivity: Double {
        get { defaults.object(forKey: "sensitivity") as? Double ?? 25 }
        set { defaults.set(newValue, forKey: "sensitivity") }
    }

    /// Head rotation slower than this (degrees/second) is ignored, which
    /// filters out sensor drift and natural micro-movements.
    var deadzone: Double {
        get { defaults.object(forKey: "deadzone") as? Double ?? 3 }
        set { defaults.set(newValue, forKey: "deadzone") }
    }

    var invertX: Bool {
        get { defaults.bool(forKey: "invertX") }
        set { defaults.set(newValue, forKey: "invertX") }
    }

    var invertY: Bool {
        get { defaults.bool(forKey: "invertY") }
        set { defaults.set(newValue, forKey: "invertY") }
    }

    /// Acceleration spike (in g) that counts as an earbud tap. Lower = more sensitive.
    var earbudTapThreshold: Double {
        get { defaults.object(forKey: "earbudTapThreshold") as? Double ?? 0.5 }
        set { defaults.set(newValue, forKey: "earbudTapThreshold") }
    }

    var debugLogging: Bool {
        get { defaults.bool(forKey: "debugLogging") }
        set { defaults.set(newValue, forKey: "debugLogging") }
    }

    func action(for gesture: Gesture) -> GestureAction {
        defaults.string(forKey: "action.\(gesture.rawValue)")
            .flatMap(GestureAction.init(rawValue:)) ?? gesture.defaultAction
    }

    func setAction(_ action: GestureAction, for gesture: Gesture) {
        defaults.set(action.rawValue, forKey: "action.\(gesture.rawValue)")
    }
}
