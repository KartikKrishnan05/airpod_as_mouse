import CoreBluetooth
import Foundation

/// Detects the AirPods case lid being opened or closed by listening to the
/// Bluetooth LE "proximity pairing" advertisements AirPods broadcast.
///
/// Packet layout (Apple manufacturer data, company ID 0x004C):
///   [0-1]  4C 00     Apple
///   [2]    07        proximity pairing message
///   [3]    length
///   [4]    01        prefix
///   [5-6]  model     e.g. 0x2024 = AirPods Pro 2 (USB-C), little-endian
///   [7]    status    in-ear / in-case flags
///   [8]    battery   left/right earbud levels
///   [9]    charging flags + case battery
///   [10]   lid       lid open counter; changes when the lid is opened/closed
///   [11]   color
///   ...    encrypted payload
///
/// The earbuds only know the lid state while at least one of them is in the
/// case, so this gesture works with an earbud (or both) in the case.
final class CaseLidMonitor: NSObject, CBCentralManagerDelegate {
    var onLidChange: (() -> Void)?
    var onStatusChange: ((String) -> Void)?

    /// Ignore packets weaker than this (dBm), so other people's AirPods nearby
    /// don't trigger clicks. Around -70 is "within a couple of metres".
    var minimumRSSI = -70

    private var central: CBCentralManager?
    private var wantsScan = false

    /// Last lid byte seen per Bluetooth identifier. AirPods rotate their
    /// address every so often, which gives them a new identifier.
    private var lidByPeripheral: [UUID: UInt8] = [:]
    /// Last lid byte seen per AirPods model, used when the identifier rotates
    /// (e.g. after the AirPods wake up because the lid was opened).
    private var lidByModel: [UInt16: UInt8] = [:]
    private var lastFire = Date.distantPast

    func start() {
        wantsScan = true
        if let central {
            startScanIfPossible(central)
        } else {
            central = CBCentralManager(delegate: self, queue: .main)
        }
    }

    func stop() {
        wantsScan = false
        central?.stopScan()
        onStatusChange?("Case lid: off")
    }

    private func startScanIfPossible(_ central: CBCentralManager) {
        guard wantsScan, central.state == .poweredOn, !central.isScanning else { return }
        central.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
        onStatusChange?("Case lid: listening")
    }

    // MARK: CBCentralManagerDelegate

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            startScanIfPossible(central)
        case .unauthorized:
            onStatusChange?("Case lid: Bluetooth permission denied")
        case .poweredOff:
            onStatusChange?("Case lid: Bluetooth is off")
        case .unsupported:
            onStatusChange?("Case lid: Bluetooth LE unsupported")
        default:
            onStatusChange?("Case lid: waiting for Bluetooth")
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        guard let data = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data else { return }
        let b = [UInt8](data)
        guard b.count >= 12, b[0] == 0x4C, b[1] == 0x00, b[2] == 0x07, b[4] == 0x01 else { return }

        let rssi = RSSI.intValue
        guard rssi != 127, rssi >= minimumRSSI else { return } // 127 = RSSI unavailable

        let model = UInt16(b[5]) | (UInt16(b[6]) << 8)
        let lid = b[10]
        let id = peripheral.identifier

        let previous = lidByPeripheral[id] ?? lidByModel[model]
        lidByPeripheral[id] = lid
        lidByModel[model] = lid

        guard let previous, previous != lid else { return }

        DebugLog.write(String(
            format: "case lid byte 0x%02x -> 0x%02x (model 0x%04x, rssi %d) packet %@",
            previous, lid, model, rssi, b.map { String(format: "%02x", $0) }.joined()
        ))

        // Opening and closing in quick succession counts as one gesture.
        let now = Date()
        guard now.timeIntervalSince(lastFire) > 1.5 else { return }
        lastFire = now
        onLidChange?()
    }
}
