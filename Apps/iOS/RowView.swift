import SwiftUI
import HealthAndICore

enum HUDTile {
    static let all = ["heart_rate", "zone", "stroke_rate", "pace", "distance", "resistance", "elapsed", "power", "energy_console", "energy_hr"]

    static func title(_ id: String) -> String {
        switch id {
        case "heart_rate": "Heart rate"
        case "zone": "Zone"
        case "stroke_rate": "Stroke rate"
        case "pace": "Pace /500 m"
        case "distance": "Distance"
        case "resistance": "Resistance"
        case "elapsed": "Elapsed"
        case "power": "Power"
        case "energy", "energy_console": "kcal (console)"
        case "energy_hr": "kcal (HR estimate)"
        default: id
        }
    }
}

/// Live rowing session state: samples BLE readings once a second into a SessionRecorder.
@MainActor @Observable
final class RowSession {
    static let shared = RowSession()

    var isRunning = false
    var start: Date?
    var elapsed: Double = 0
    var hrSourceChoice: Source = .polarH10
    var zoneState: ZoneState?
    var hrKcal: Double?
    var lastSaved: Session?

    @ObservationIgnored private var recorder: SessionRecorder?
    @ObservationIgnored private var ticker: Task<Void, Never>?

    private var ble: BLEManager { BLEManager.shared }
    private var store: StoreController { StoreController.shared }

    var zoneSetId: String? {
        get { UserDefaults.standard.string(forKey: "row_zone_set") }
        set { UserDefaults.standard.set(newValue, forKey: "row_zone_set"); rebuildEngine() }
    }
    var zoneName: String? {
        get { UserDefaults.standard.string(forKey: "row_zone_name") }
        set { UserDefaults.standard.set(newValue, forKey: "row_zone_name"); rebuildEngine() }
    }

    var zoneSet: ZoneSet? {
        let cat = store.catalogue
        if let id = zoneSetId, let zs = cat.zoneSet(id: id) { return zs }
        if let t = cat.targets.first(where: { $0.enabled && $0.zoneSetId != nil }), let zs = cat.zoneSet(id: t.zoneSetId!) { return zs }
        return cat.zoneSets.first { $0.metric == .heartRate }
    }

    var zone: Zone? {
        guard let zs = zoneSet else { return nil }
        if let n = zoneName, let z = zs.zone(named: n) { return z }
        if let t = store.catalogue.targets.first(where: { $0.zoneSetId == zs.id }), let n = t.zoneName, let z = zs.zone(named: n) { return z }
        return zs.zones.first
    }

    var heartRate: Int? {
        switch hrSourceChoice {
        case .machine: ble.rowerData?.heartRate ?? (ble.hrSource == .machine ? ble.heartRate : nil)
        case .appleWatch: watchHeartRate()
        default: ble.hrSource == .machine ? nil : ble.heartRate
        }
    }

    func liveZoneState() -> ZoneState? {
        guard let hr = heartRate else { return nil }
        if isRunning, let s = zoneState { return s }
        guard let zs = zoneSet, let z = zone else { return nil }
        return ZoneEngine(zoneSet: zs, zoneName: z.name).state(for: Double(hr))
    }

    private func rebuildEngine() {
        guard let zs = zoneSet, let z = zone else { return }
        let cues = ZoneCueService.shared
        cues.configure(zoneSet: zs, zoneName: z.name)
        cues.enabled = store.catalogue.settings.zoneCues
    }

    func begin() {
        let now = Date()
        start = now
        elapsed = 0
        hrKcal = nil
        zoneState = nil
        recorder = SessionRecorder(start: now)
        rebuildEngine()
        isRunning = true
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                self?.tick()
            }
        }
    }

    private func tick() {
        guard isRunning, let start, var rec = recorder else { return }
        let now = Date()
        elapsed = now.timeIntervalSince(start)
        if let hr = heartRate {
            rec.add(metric: "heart_rate", unit: "bpm", source: hrSourceChoice, value: Double(hr), at: now)
            if zone != nil {
                ZoneCueService.shared.update(hr: hr, at: now)
                zoneState = ZoneCueService.shared.state
            }
        }
        if let d = ble.rowerData {
            func add(_ m: String, _ u: String, _ v: Double?) {
                if let v { rec.add(metric: m, unit: u, source: .machine, value: v, at: now) }
            }
            add("stroke_rate", "spm", d.strokeRate)
            add("stroke_count", "strokes", d.strokeCount.map(Double.init))
            add("pace_s_per_500m", "s", d.instantaneousPaceSPer500m.map(Double.init))
            add("distance_m", "m", d.totalDistanceM.map(Double.init))
            add("resistance", "level", d.resistanceLevel.map(Double.init))
            add("power_w", "W", d.instantaneousPowerW.map(Double.init))
            add("energy_kcal", "kcal", d.totalEnergyKcal.map(Double.init))
        }
        recorder = rec
        if Int(elapsed) % 10 == 0, let hrSeries = rec.series().first(where: { $0.metric == "heart_rate" }) {
            hrKcal = EnergyEstimator.kcal(hrSeries: hrSeries, profile: store.catalogue.profile)
        }
        sendHUD()
    }

    func finish() {
        ticker?.cancel()
        ticker = nil
        isRunning = false
        guard let start, let rec = recorder else { return }
        let end = Date()
        let series = rec.series()
        var summary = rec.summary(zoneSet: zoneSet, zoneName: zone?.name)
        if let hrSeries = series.first(where: { $0.metric == "heart_rate" }),
           let kcal = EnergyEstimator.kcal(hrSeries: hrSeries, profile: store.catalogue.profile) {
            summary["energy_kcal_hr"] = kcal
        }
        summary["duration_s"] = end.timeIntervalSince(start)
        let equipment = [ble.connectedRower?.equipmentId].compactMap { $0 }
        let session = Session(
            id: SessionID.make(start: start, type: "rowing"),
            start: start, end: end, type: "rowing",
            hrSource: series.contains { $0.metric == "heart_rate" } ? hrSourceChoice : nil,
            equipmentIds: equipment, intervals: series, summary: summary)
        store.saveSession(session)
        store.writeDerived()
        lastSaved = session
        recorder = nil
        pushToHealthKit(session)
    }

    // MARK: Service hooks

    private func watchHeartRate() -> Int? {
        guard let snap = WatchBridge.shared.latestSnapshot, Date().timeIntervalSince(snap.sentAt) < 10 else { return nil }
        return snap.hr
    }

    private func sendHUD() {
        let d = ble.rowerData
        WatchBridge.shared.send(snapshot: HUDSnapshot(
            hr: heartRate, zoneState: zoneState?.rawValue, strokeRate: d?.strokeRate,
            pace: d?.instantaneousPaceSPer500m, distance: d?.totalDistanceM.map(Double.init),
            resistance: d?.resistanceLevel, elapsed: elapsed, sessionActive: isRunning))
    }

    private func pushToHealthKit(_ session: Session) {
        HealthPush.workout(session, activity: .rowing)
    }
}

enum SessionID {
    static func make(start: Date, type: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd-HHmm"
        return "\(f.string(from: start))-\(type)"
    }
}

struct RowView: View {
    @State private var row = RowSession.shared
    @State private var showDebug = false
    @State private var showDevices = false
    private var ble: BLEManager { BLEManager.shared }
    private var store: StoreController { StoreController.shared }

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    controls
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(store.catalogue.settings.hudTiles, id: \.self) { tile in
                            tileView(tile)
                                .contextMenu {
                                    Button("Move earlier") { move(tile, by: -1) }
                                    Button("Move later") { move(tile, by: 1) }
                                    Button("Hide", role: .destructive) {
                                        store.catalogue.settings.hudTiles.removeAll { $0 == tile }
                                        store.save()
                                    }
                                }
                        }
                    }
                    startStop
                    if let s = row.lastSaved, !row.isRunning {
                        Text("Saved \(s.id): \(Fmt.summaryLine(s))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
            .navigationTitle("Row")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Devices", systemImage: "antenna.radiowaves.left.and.right") { showDevices = true }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Debug", systemImage: "ladybug") { showDebug = true }
                }
            }
            .sheet(isPresented: $showDevices) { DevicePicker() }
            .sheet(isPresented: $showDebug) { BLEDebugView() }
        }
    }

    private var controls: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: ble.isConnected ? "dot.radiowaves.left.and.right" : "wifi.slash")
                Text([ble.connectedRower?.name, ble.connectedHR?.name].compactMap { $0 }.joined(separator: " + ").nonEmpty ?? "Not connected")
                    .font(.subheadline)
                Spacer()
                if !ble.isConnected { Button("Connect…") { showDevices = true } }
            }
            Picker("HR source", selection: $row.hrSourceChoice) {
                Text("Polar H10").tag(Source.polarH10)
                Text("Apple Watch").tag(Source.appleWatch)
                Text("Machine").tag(Source.machine)
            }
            .pickerStyle(.segmented)
            .disabled(row.isRunning)
            HStack {
                Picker("Zone set", selection: Binding(get: { row.zoneSet?.id }, set: { row.zoneSetId = $0; row.zoneName = nil })) {
                    ForEach(store.catalogue.zoneSets) { Text($0.name).tag(String?.some($0.id)) }
                }
                if let zs = row.zoneSet {
                    Picker("Zone", selection: Binding(get: { row.zone?.name }, set: { row.zoneName = $0 })) {
                        ForEach(zs.zones, id: \.name) { Text($0.name).tag(String?.some($0.name)) }
                    }
                }
            }
            .disabled(row.isRunning)
        }
    }

    private var startStop: some View {
        Button {
            if row.isRunning { row.finish() } else { row.begin() }
        } label: {
            Text(row.isRunning ? "Stop and save" : "Start")
                .font(.title2.bold())
                .frame(maxWidth: .infinity)
                .padding()
        }
        .buttonStyle(.borderedProminent)
        .tint(row.isRunning ? .red : .green)
    }

    private func move(_ tile: String, by delta: Int) {
        var tiles = store.catalogue.settings.hudTiles
        guard let i = tiles.firstIndex(of: tile) else { return }
        let j = i + delta
        guard tiles.indices.contains(j) else { return }
        tiles.swapAt(i, j)
        store.catalogue.settings.hudTiles = tiles
        store.save()
    }

    private func zoneColor(_ state: ZoneState?) -> Color {
        switch state {
        case .inBand: .green
        case .below: .blue
        case .above: .red
        case nil: .gray
        }
    }

    @ViewBuilder
    private func tileView(_ id: String) -> some View {
        let d = ble.rowerData
        let state = row.liveZoneState()
        switch id {
        case "heart_rate":
            HUDTileView(title: "HR (\(row.hrSourceChoice.rawValue))",
                        value: row.heartRate.map(String.init) ?? "–",
                        detail: row.zone.map { "\(row.zoneSet?.name ?? "") \($0.name) \(Fmt.number($0.lower))–\(Fmt.number($0.upper))" },
                        color: zoneColor(state))
        case "zone":
            HUDTileView(title: "Zone", value: {
                switch state {
                case .inBand: "In band"
                case .below: "Below"
                case .above: "Above"
                case nil: "–"
                }
            }(), detail: row.zone?.name, color: zoneColor(state))
        case "stroke_rate":
            HUDTileView(title: "Stroke rate", value: d?.strokeRate.map { Fmt.number($0) } ?? "–", detail: "spm")
        case "pace":
            HUDTileView(title: "Pace /500 m", value: d?.instantaneousPaceSPer500m.map { Fmt.duration(Double($0)) } ?? "–")
        case "distance":
            HUDTileView(title: "Distance", value: d?.totalDistanceM.map { "\($0)" } ?? "–", detail: "m")
        case "resistance":
            HUDTileView(title: "Resistance", value: d?.resistanceLevel.map { "\($0)" } ?? "–")
        case "elapsed":
            HUDTileView(title: "Elapsed", value: row.isRunning ? Fmt.duration(row.elapsed) : (d?.elapsedSeconds.map { Fmt.duration(Double($0)) } ?? "0:00"))
        case "power":
            HUDTileView(title: "Power", value: d?.instantaneousPowerW.map { "\($0)" } ?? "–", detail: "W")
        case "energy", "energy_console":
            HUDTileView(title: "kcal (console)", value: d?.totalEnergyKcal.map { "\($0)" } ?? "–", detail: "from distance/pace")
        case "energy_hr":
            HUDTileView(title: "kcal (HR estimate)", value: row.hrKcal.map { Fmt.number($0, digits: 0) } ?? "–", detail: "Keytel, needs profile")
        default:
            HUDTileView(title: id, value: "–")
        }
    }
}

struct HUDTileView: View {
    let title: String
    let value: String
    var detail: String? = nil
    var color: Color = .secondary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 44, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            if let detail { Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
        }
        .frame(maxWidth: .infinity, minHeight: 110, alignment: .leading)
        .padding(12)
        .background(color.opacity(0.18), in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(color.opacity(0.6), lineWidth: 2))
    }
}

struct DevicePicker: View {
    @Environment(\.dismiss) private var dismiss
    private var ble: BLEManager { BLEManager.shared }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if !ble.isPoweredOn { Text("Bluetooth is off or not authorised.").foregroundStyle(.secondary) }
                    Button(ble.isScanning ? "Stop scanning" : "Scan") {
                        if ble.isScanning { ble.stopScan() } else { ble.startScan() }
                    }
                }
                Section("Discovered") {
                    ForEach(ble.discovered) { dev in
                        let connected = ble.connectedRower?.id == dev.id || ble.connectedHR?.id == dev.id
                        Button {
                            if connected { ble.disconnect(dev) } else { ble.connect(dev) }
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(dev.name)
                                    Text([dev.isRower ? "rower (FTMS)" : nil, dev.isHeartRate ? "heart rate" : nil, "RSSI \(dev.rssi)"].compactMap { $0 }.joined(separator: " · "))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if connected { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Devices")
            .toolbar { Button("Done") { dismiss() } }
            .onAppear { if !ble.isScanning { ble.startScan() } }
            .onDisappear { ble.stopScan() }
        }
    }
}

struct BLEDebugView: View {
    @Environment(\.dismiss) private var dismiss
    private var ble: BLEManager { BLEManager.shared }

    var body: some View {
        NavigationStack {
            List {
                Section("Fitness Machine Feature") {
                    if let f = ble.rowerFeature {
                        LabeledContent("Machine flags", value: String(format: "0x%08X", f.fitnessMachineFeatures))
                        LabeledContent("Target flags", value: String(format: "0x%08X", f.targetSettingFeatures))
                        flag("Cadence", f.supportsCadence)
                        flag("Total distance", f.supportsTotalDistance)
                        flag("Pace", f.supportsPace)
                        flag("Resistance level", f.supportsResistanceLevel)
                        flag("Expended energy", f.supportsExpendedEnergy)
                        flag("Heart rate", f.supportsHeartRate)
                        flag("Power", f.supportsPower)
                        flag("Resistance target", f.supportsResistanceTarget)
                        flag("Power target", f.supportsPowerTarget)
                        flag("HR target", f.supportsHeartRateTarget)
                    } else {
                        Text("Not read yet (connect a rower).").foregroundStyle(.secondary)
                    }
                    LabeledContent("Control allowed", value: ble.allowControl ? "yes" : "no")
                    LabeledContent("Control granted", value: ble.hasControl ? "yes" : "no")
                }
                Section("Log") {
                    ForEach(Array(ble.log.reversed().enumerated()), id: \.offset) { _, line in
                        Text(line).font(.system(.caption2, design: .monospaced))
                    }
                }
            }
            .navigationTitle("BLE debug")
            .toolbar { Button("Done") { dismiss() } }
        }
    }

    private func flag(_ name: String, _ on: Bool) -> some View {
        LabeledContent(name) {
            Image(systemName: on ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(on ? .green : .secondary)
        }
    }
}

extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
