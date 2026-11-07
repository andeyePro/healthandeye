import Foundation
import Observation
@preconcurrency import CoreBluetooth
import HealthAndICore

struct DiscoveredDevice: Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var rssi: Int
    var isRower: Bool
    var isHeartRate: Bool
    /// Catalogue equipment whose `connection.bleName` prefixes this device's name.
    var equipmentId: String?
}

/// Scans for FTMS rowers (0x1826) and HR straps (0x180D); publishes parsed live data.
@Observable @MainActor
final class BLEManager: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    static let shared = BLEManager()

    var discovered: [DiscoveredDevice] = []
    var rowerData: FTMSRowerData?
    var rowerFeature: FTMSFeature?
    var heartRate: Int?
    var hrSource: Source?
    var isScanning = false
    var isPoweredOn = false
    var connectedRower: DiscoveredDevice?
    var connectedHR: DiscoveredDevice?
    var isConnected: Bool { connectedRower != nil || connectedHR != nil }
    /// Control-point writes are refused unless this is true (closed-loop module, post-v1).
    var allowControl = false
    var hasControl = false
    var log: [String] = []

    /// Hooks for a session recorder; called on every parsed notification.
    @ObservationIgnored var onRowerData: ((FTMSRowerData) -> Void)?
    @ObservationIgnored var onHeartRate: ((Int, Source) -> Void)?

    @ObservationIgnored private var central: CBCentralManager?
    @ObservationIgnored private var peripherals: [UUID: CBPeripheral] = [:]
    @ObservationIgnored private var controlPoint: CBCharacteristic?
    @ObservationIgnored private var pendingResistance: Double?

    nonisolated private static let ftmsService = CBUUID(string: FTMSUUID.service)
    nonisolated private static let hrService = CBUUID(string: FTMSUUID.hrService)
    private static let rowerDataChar = CBUUID(string: FTMSUUID.rowerData)
    private static let featureChar = CBUUID(string: FTMSUUID.feature)
    private static let controlPointChar = CBUUID(string: FTMSUUID.controlPoint)
    private static let statusChar = CBUUID(string: FTMSUUID.status)
    private static let trainingStatusChar = CBUUID(string: FTMSUUID.trainingStatus)
    private static let hrMeasurementChar = CBUUID(string: FTMSUUID.hrMeasurement)

    override init() {
        super.init()
    }

    // MARK: Public API

    func startScan() {
        if central == nil {
            central = CBCentralManager(delegate: self, queue: .main)
            isScanning = true
            return // scanning begins once the manager reports poweredOn
        }
        guard let central, central.state == .poweredOn else { isScanning = true; return }
        isScanning = true
        central.scanForPeripherals(withServices: [Self.ftmsService, Self.hrService],
                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        note("scan started")
    }

    func stopScan() {
        central?.stopScan()
        isScanning = false
    }

    func connect(_ device: DiscoveredDevice) {
        guard let central, let p = peripherals[device.id] else { return }
        p.delegate = self
        central.connect(p)
        note("connecting \(device.name)")
    }

    /// Disconnect one device, or everything when `device` is nil.
    func disconnect(_ device: DiscoveredDevice? = nil) {
        guard let central else { return }
        let ids = device.map { [$0.id] } ?? [connectedRower?.id, connectedHR?.id].compactMap { $0 }
        for id in ids {
            if let p = peripherals[id] { central.cancelPeripheralConnection(p) }
        }
    }

    /// FTMS Set Target Resistance Level. No-op unless `allowControl` is true.
    func setResistance(_ level: Double) {
        guard allowControl else { note("resistance write refused: control disabled"); return }
        guard let cp = controlPoint, let p = cp.service?.peripheral else { note("no control point"); return }
        if !hasControl {
            pendingResistance = level
            p.writeValue(FTMSControlPoint.requestControl(), for: cp, type: .withResponse)
            note("request control")
            return
        }
        p.writeValue(FTMSControlPoint.setResistanceLevel(level), for: cp, type: .withResponse)
        note("set resistance \(level)")
    }

    // MARK: Helpers

    private func note(_ line: String) {
        let stamp = Date.now.formatted(date: .omitted, time: .standard)
        log.append("\(stamp) \(line)")
        if log.count > 50 { log.removeFirst(log.count - 50) }
    }

    private func equipmentId(forName name: String) -> String? {
        StoreController.shared.catalogue.equipment.first { eq in
            guard eq.enabled, let prefix = eq.connection?.bleName, !prefix.isEmpty else { return false }
            return name.lowercased().hasPrefix(prefix.lowercased())
        }?.id
    }

    private func device(for p: CBPeripheral) -> DiscoveredDevice? {
        discovered.first { $0.id == p.identifier }
    }

    // MARK: CBCentralManagerDelegate (delivered on the main queue)

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        MainActor.assumeIsolated {
            isPoweredOn = central.state == .poweredOn
            note("bluetooth state \(central.state.rawValue)")
            if isPoweredOn && isScanning { startScan() }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let services = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []
        let advName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let rssi = RSSI.intValue
        let advertisesRower = services.contains(Self.ftmsService)
        let advertisesHR = services.contains(Self.hrService)
        MainActor.assumeIsolated {
            let name = advName ?? peripheral.name ?? "Unknown"
            peripherals[peripheral.identifier] = peripheral
            var d = DiscoveredDevice(id: peripheral.identifier, name: name, rssi: rssi,
                                     isRower: advertisesRower,
                                     isHeartRate: advertisesHR,
                                     equipmentId: equipmentId(forName: name))
            if let i = discovered.firstIndex(where: { $0.id == d.id }) {
                d.isRower = d.isRower || discovered[i].isRower
                d.isHeartRate = d.isHeartRate || discovered[i].isHeartRate
                discovered[i] = d
            } else {
                discovered.append(d)
                note("found \(name)\(d.isRower ? " [FTMS]" : "")\(d.isHeartRate ? " [HR]" : "")")
                discovered.sort { ($0.equipmentId != nil ? 0 : 1, -$0.rssi) < ($1.equipmentId != nil ? 0 : 1, -$1.rssi) }
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        MainActor.assumeIsolated {
            note("connected \(peripheral.name ?? peripheral.identifier.uuidString)")
            peripheral.discoverServices([Self.ftmsService, Self.hrService])
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        let msg = error?.localizedDescription ?? "unknown error"
        MainActor.assumeIsolated { note("connect failed: \(msg)") }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        MainActor.assumeIsolated {
            note("disconnected \(peripheral.name ?? peripheral.identifier.uuidString)")
            if connectedRower?.id == peripheral.identifier {
                connectedRower = nil
                rowerData = nil
                rowerFeature = nil
                controlPoint = nil
                hasControl = false
                if hrSource == .machine { heartRate = nil; hrSource = nil }
            }
            if connectedHR?.id == peripheral.identifier {
                connectedHR = nil
                heartRate = nil
                hrSource = nil
            }
        }
    }

    // MARK: CBPeripheralDelegate

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        MainActor.assumeIsolated {
            for service in peripheral.services ?? [] {
                if service.uuid == Self.ftmsService {
                    connectedRower = device(for: peripheral)
                    peripheral.discoverCharacteristics([Self.rowerDataChar, Self.featureChar, Self.controlPointChar,
                                                        Self.statusChar, Self.trainingStatusChar], for: service)
                } else if service.uuid == Self.hrService {
                    // A rower that also relays HR keeps its HR as `.machine`; a dedicated strap wins.
                    if connectedRower?.id != peripheral.identifier { connectedHR = device(for: peripheral) }
                    peripheral.discoverCharacteristics([Self.hrMeasurementChar], for: service)
                }
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        MainActor.assumeIsolated {
            for c in service.characteristics ?? [] {
                switch c.uuid {
                case Self.rowerDataChar, Self.statusChar, Self.trainingStatusChar, Self.hrMeasurementChar:
                    peripheral.setNotifyValue(true, for: c)
                case Self.featureChar:
                    peripheral.readValue(for: c)
                case Self.controlPointChar:
                    controlPoint = c
                    peripheral.setNotifyValue(true, for: c) // indications carry the responses
                default:
                    break
                }
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
        let uuid = characteristic.uuid
        MainActor.assumeIsolated {
            handle(data: data, from: uuid, peripheral: peripheral.identifier)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        let msg = error?.localizedDescription
        MainActor.assumeIsolated {
            if let msg { note("write failed: \(msg)") }
        }
    }

    private func handle(data: Data, from uuid: CBUUID, peripheral: UUID) {
        switch uuid {
        case Self.rowerDataChar:
            guard let parsed = FTMSRowerData.parse(data) else { note("unparsed rower data \(data.count)B"); return }
            rowerData = parsed
            if let hr = parsed.heartRate, hr > 0, connectedHR == nil {
                heartRate = hr
                hrSource = .machine
                onHeartRate?(hr, .machine)
            }
            onRowerData?(parsed)
        case Self.featureChar:
            rowerFeature = FTMSFeature.parse(data)
            note("feature read")
        case Self.hrMeasurementChar:
            guard let m = HeartRateMeasurement.parse(data) else { return }
            let source: Source = connectedRower?.id == peripheral ? .machine : .polarH10
            if source == .machine && connectedHR != nil { return }
            heartRate = m.bpm
            hrSource = source
            onHeartRate?(m.bpm, source)
        case Self.controlPointChar:
            guard let r = FTMSControlPoint.parseResponse(data) else { return }
            note("control point op \(r.op) result \(r.result)")
            if r.op == 0x00 {
                hasControl = r.result == 0x01
                if hasControl, let level = pendingResistance {
                    pendingResistance = nil
                    setResistance(level)
                }
            }
        default:
            note("\(uuid.uuidString) \(data.map { String(format: "%02x", $0) }.joined())")
        }
    }
}
