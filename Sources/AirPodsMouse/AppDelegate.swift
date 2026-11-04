import AppKit
import ApplicationServices

/// Menu bar app that wires AirPods input to the cursor:
///   head movement            → move cursor
///   stem presses ×1 / ×2 / ×3 → configurable (default: left click, right click, pause)
///   tap on an earbud         → configurable (default: left click)
///   case lid open/close      → configurable (default: left click)
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = Settings.shared
    private let motion = HeadMotionController()
    private let cursor = CursorController()
    private let stemPresses = TapController()
    private let caseLid = CaseLidMonitor()

    private var statusItem: NSStatusItem!
    private let connectionItem = NSMenuItem(title: "AirPods: waiting…", action: nil, keyEquivalent: "")
    private let accessibilityItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let caseLidStatusItem = NSMenuItem(title: "Case lid: off", action: nil, keyEquivalent: "")
    private var trackingItem: NSMenuItem!
    private var invertXItem: NSMenuItem!
    private var invertYItem: NSMenuItem!
    private var debugLogItem: NSMenuItem!
    private var sensitivityItems: [NSMenuItem] = []
    private var tapSensitivityItems: [NSMenuItem] = []
    private var gestureActionItems: [NSMenuItem] = []

    private var trackingEnabled = true {
        didSet {
            motion.resetReference()
            cursor.cancelPending()
            refreshMenu()
        }
    }

    private let sensitivityPresets: [(String, Double)] = [
        ("Low", 12), ("Medium", 25), ("High", 40), ("Very High", 60),
    ]
    /// Earbud tap thresholds in g: lower = triggers on lighter taps.
    private let tapSensitivityPresets: [(String, Double)] = [
        ("Low (firm taps)", 0.8), ("Medium", 0.5), ("High", 0.3), ("Very High (light taps)", 0.2),
    ]

    // Earbud tap state.
    /// Cursor position when the latest tap spike began, before the jolt moved it.
    private var tapStartLocation: CGPoint?
    private var pendingEarbudTap: DispatchWorkItem?
    private var pendingEarbudTapLocation: CGPoint?
    private let doubleTapWindow: TimeInterval = 0.45

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildStatusItem()
        requestAccessibility()

        // Head motion → cursor.
        motion.tapDetector.threshold = settings.earbudTapThreshold
        motion.onDelta = { [weak self] dYaw, dPitch, dt in
            self?.handleHeadDelta(dYaw: dYaw, dPitch: dPitch, dt: dt)
        }
        motion.onConnectionChange = { [weak self] connected in
            self?.connectionItem.title = connected ? "AirPods: connected" : "AirPods: disconnected"
        }
        motion.onError = { [weak self] message in
            self?.connectionItem.title = message
        }

        // Earbud taps.
        motion.onTapCandidate = { [weak self] in
            guard let self else { return }
            self.tapStartLocation = self.cursor.currentLocation()
        }
        motion.onEarbudTap = { [weak self] in self?.handleEarbudTap() }

        // Stem presses.
        stemPresses.onSingle = { [weak self] in self?.perform(.stemSingle) }
        stemPresses.onDouble = { [weak self] in self?.perform(.stemDouble) }
        stemPresses.onTriple = { [weak self] in self?.perform(.stemTriple) }

        // Case lid.
        caseLid.onLidChange = { [weak self] in self?.perform(.caseLid) }
        caseLid.onStatusChange = { [weak self] status in self?.caseLidStatusItem.title = status }

        cursor.start()
        motion.start()
        stemPresses.start()
        updateCaseLidMonitoring()

        // Refresh accessibility status periodically so the menu reflects a grant
        // made in System Settings without restarting.
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.refreshMenu()
        }
    }

    // MARK: Head motion → cursor

    private func handleHeadDelta(dYaw: Double, dPitch: Double, dt: Double) {
        guard trackingEnabled else { return }

        let speed = hypot(dYaw, dPitch) / dt // deg/s
        guard speed > settings.deadzone else { return }

        // Mild acceleration: slow head movement = precise, fast = covers distance.
        let accel = 1 + speed / 90

        // Turning right (dYaw < 0) moves the cursor right; tilting up moves it up
        // (screen y grows downward).
        var dx = -dYaw * settings.sensitivity * accel
        var dy = -dPitch * settings.sensitivity * accel
        if settings.invertX { dx = -dx }
        if settings.invertY { dy = -dy }

        cursor.enqueue(dx: dx, dy: dy)
    }

    // MARK: Gestures → actions

    private func handleEarbudTap() {
        let location = tapStartLocation

        // No double-tap action: fire the single tap right away (no delay).
        guard settings.action(for: .earbudDoubleTap) != .none else {
            perform(.earbudTap, at: location)
            return
        }

        // Second tap inside the window → double tap.
        if let pending = pendingEarbudTap {
            pending.cancel()
            pendingEarbudTap = nil
            perform(.earbudDoubleTap, at: pendingEarbudTapLocation)
            return
        }

        // First tap: wait briefly to see whether a second tap follows.
        let item = DispatchWorkItem { [weak self] in
            self?.pendingEarbudTap = nil
            self?.perform(.earbudTap, at: location)
        }
        pendingEarbudTap = item
        pendingEarbudTapLocation = location
        DispatchQueue.main.asyncAfter(deadline: .now() + doubleTapWindow, execute: item)
    }

    private func perform(_ gesture: Gesture, at location: CGPoint? = nil) {
        let action = settings.action(for: gesture)

        if action == .toggleTracking {
            trackingEnabled.toggle()
            NSSound(named: trackingEnabled ? "Tink" : "Bottle")?.play()
            return
        }
        // While paused, only the pause/resume gesture does anything.
        guard trackingEnabled else { return }

        switch action {
        case .none, .toggleTracking: break
        case .leftClick: cursor.click(.left, at: location)
        case .rightClick: cursor.click(.right, at: location)
        case .middleClick: cursor.click(.center, at: location)
        case .doubleClick: cursor.click(.left, count: 2, at: location)
        }
    }

    private func updateCaseLidMonitoring() {
        // Only scan Bluetooth when the lid gesture is actually in use.
        if settings.action(for: .caseLid) == .none {
            caseLid.stop()
        } else {
            caseLid.start()
        }
    }

    // MARK: Accessibility

    private func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    @objc private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    // MARK: Menu

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "airpodspro", accessibilityDescription: "AirPods Mouse")
                ?? NSImage(systemSymbolName: "headphones", accessibilityDescription: "AirPods Mouse")
            image?.isTemplate = true
            button.image = image
        }

        let menu = NSMenu()
        menu.autoenablesItems = false

        for item in [connectionItem, accessibilityItem, caseLidStatusItem] {
            item.isEnabled = false
            menu.addItem(item)
        }
        menu.addItem(.separator())

        trackingItem = addItem(to: menu, "Tracking Enabled", #selector(toggleTracking), key: "t")
        menu.addItem(submenuItem("Sensitivity", presets: sensitivityPresets,
                                 action: #selector(selectSensitivity(_:)), into: &sensitivityItems))
        invertXItem = addItem(to: menu, "Invert Horizontal", #selector(toggleInvertX))
        invertYItem = addItem(to: menu, "Invert Vertical", #selector(toggleInvertY))
        menu.addItem(.separator())

        menu.addItem(buildGesturesMenuItem())
        menu.addItem(.separator())

        addItem(to: menu, "Reclaim AirPods Controls", #selector(reclaimControls), key: "r")
        addItem(to: menu, "Open Accessibility Settings…", #selector(openAccessibilitySettings))
        debugLogItem = addItem(to: menu, "Debug Log", #selector(toggleDebugLog))
        addItem(to: menu, "Show Debug Log", #selector(showDebugLog))
        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: "Quit AirPods Mouse", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem.menu = menu
        refreshMenu()
    }

    private func buildGesturesMenuItem() -> NSMenuItem {
        let gesturesMenu = NSMenu()
        gesturesMenu.autoenablesItems = false

        for gesture in Gesture.allCases {
            if gesture == .earbudTap || gesture == .caseLid {
                gesturesMenu.addItem(.separator())
            }
            let actionsMenu = NSMenu()
            for action in GestureAction.allCases {
                let item = NSMenuItem(title: action.title, action: #selector(selectGestureAction(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = "\(gesture.rawValue)|\(action.rawValue)"
                actionsMenu.addItem(item)
                gestureActionItems.append(item)
            }
            let gestureItem = NSMenuItem(title: gesture.title, action: nil, keyEquivalent: "")
            gestureItem.submenu = actionsMenu
            gesturesMenu.addItem(gestureItem)

            if gesture == .earbudDoubleTap {
                gesturesMenu.addItem(submenuItem("Earbud Tap Sensitivity", presets: tapSensitivityPresets,
                                                 action: #selector(selectTapSensitivity(_:)),
                                                 into: &tapSensitivityItems))
            }
        }

        let item = NSMenuItem(title: "Gestures", action: nil, keyEquivalent: "")
        item.submenu = gesturesMenu
        return item
    }

    @discardableResult
    private func addItem(to menu: NSMenu, _ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
        return item
    }

    private func submenuItem(_ title: String, presets: [(String, Double)], action: Selector,
                             into items: inout [NSMenuItem]) -> NSMenuItem {
        let submenu = NSMenu()
        for (index, preset) in presets.enumerated() {
            let item = NSMenuItem(title: preset.0, action: action, keyEquivalent: "")
            item.target = self
            item.tag = index
            submenu.addItem(item)
            items.append(item)
        }
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        parent.submenu = submenu
        return parent
    }

    private func refreshMenu() {
        trackingItem?.state = trackingEnabled ? .on : .off
        invertXItem?.state = settings.invertX ? .on : .off
        invertYItem?.state = settings.invertY ? .on : .off
        debugLogItem?.state = settings.debugLogging ? .on : .off
        for (index, item) in sensitivityItems.enumerated() {
            item.state = sensitivityPresets[index].1 == settings.sensitivity ? .on : .off
        }
        for (index, item) in tapSensitivityItems.enumerated() {
            item.state = tapSensitivityPresets[index].1 == settings.earbudTapThreshold ? .on : .off
        }
        for item in gestureActionItems {
            guard let (gesture, action) = parseGestureAction(item) else { continue }
            item.state = settings.action(for: gesture) == action ? .on : .off
        }
        accessibilityItem.title = AXIsProcessTrusted()
            ? "Accessibility: granted"
            : "Accessibility: NOT granted (cursor can't move)"
        statusItem?.button?.appearsDisabled = !trackingEnabled
    }

    private func parseGestureAction(_ item: NSMenuItem) -> (Gesture, GestureAction)? {
        guard let parts = (item.representedObject as? String)?.split(separator: "|"), parts.count == 2,
              let gesture = Gesture(rawValue: String(parts[0])),
              let action = GestureAction(rawValue: String(parts[1])) else { return nil }
        return (gesture, action)
    }

    // MARK: Menu actions

    @objc private func toggleTracking() { trackingEnabled.toggle() }

    @objc private func selectSensitivity(_ sender: NSMenuItem) {
        settings.sensitivity = sensitivityPresets[sender.tag].1
        refreshMenu()
    }

    @objc private func selectTapSensitivity(_ sender: NSMenuItem) {
        settings.earbudTapThreshold = tapSensitivityPresets[sender.tag].1
        motion.tapDetector.threshold = settings.earbudTapThreshold
        refreshMenu()
    }

    @objc private func selectGestureAction(_ sender: NSMenuItem) {
        guard let (gesture, action) = parseGestureAction(sender) else { return }
        settings.setAction(action, for: gesture)
        if gesture == .caseLid { updateCaseLidMonitoring() }
        refreshMenu()
    }

    @objc private func toggleInvertX() {
        settings.invertX.toggle()
        refreshMenu()
    }

    @objc private func toggleInvertY() {
        settings.invertY.toggle()
        refreshMenu()
    }

    @objc private func toggleDebugLog() {
        settings.debugLogging.toggle()
        DebugLog.write("debug log enabled")
        refreshMenu()
    }

    @objc private func showDebugLog() {
        if !FileManager.default.fileExists(atPath: DebugLog.url.path) {
            FileManager.default.createFile(atPath: DebugLog.url.path, contents: nil)
        }
        NSWorkspace.shared.open(DebugLog.url)
    }

    @objc private func reclaimControls() { stemPresses.claimNowPlaying() }
}
