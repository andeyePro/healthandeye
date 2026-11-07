import SwiftUI
import HealthAndICore

/// One rowing session on the watch: the HKWorkoutSession supplies HR (wrist or paired strap),
/// the phone's HUD snapshot supplies rower metrics, and the zone engine drives haptic cues.
@MainActor @Observable
final class RowModel {
    private(set) var running = false
    private(set) var start: Date?
    private(set) var hr: Int?
    private(set) var zoneState: ZoneState?
    private(set) var zoneName: String?
    private var zoneSet: ZoneSet?
    private var recorder: SessionRecorder?
    private var hrSource: Source = .appleWatch
    private var ticker: Task<Void, Never>?

    let workout = WorkoutSessionController.shared
    private var store: StoreController { .shared }
    private var bridge: WatchBridge { .shared }
    private var ble: BLEManager { .shared }

    var snapshot: HUDSnapshot? { bridge.latestSnapshot }

    func begin() {
        guard !running else { return }
        let now = Date()
        start = now
        recorder = SessionRecorder(start: now)
        configureZone()
        running = true
        Task { await workout.start(activity: .rowing) }
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                self?.tick()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func finish() {
        guard running, let start else { return }
        running = false
        ticker?.cancel()
        ticker = nil
        let end = Date.now
        let phoneRecording = snapshot?.sessionActive == true
        let session = recorder.map {
            Session(
                id: Self.sessionId(start: start, type: "rowing"),
                start: start, end: end, type: "rowing",
                hrSource: hrSource,
                intervals: $0.series(),
                summary: $0.summary(zoneSet: zoneSet, zoneName: zoneName))
        }
        let saveHealth = store.isOn(.healthKitWrite)
        Task {
            let workoutId = await workout.stop(save: saveHealth)
            guard !phoneRecording, var session else { return }
            session.healthKitWorkoutId = workoutId
            store.saveSession(session)
        }
        recorder = nil
        hr = nil
        zoneState = nil
    }

    private func configureZone() {
        let cues = ZoneCueService.shared
        cues.configure(catalogue: store.catalogue)
        zoneSet = store.catalogue.zoneSets.first { $0.id == cues.zoneSetId }
        zoneName = cues.zoneName
    }

    private func tick() {
        let now = Date()
        if let w = workout.heartRate {
            hr = w
            hrSource = .appleWatch
        } else if let h = ble.heartRate {
            hr = h
            hrSource = ble.hrSource ?? .polarH10
        } else if let h = snapshot?.hr {
            hr = h
        } else {
            hr = nil
        }

        if let hr {
            recorder?.add(metric: "heart_rate", unit: "bpm", source: hrSource, value: Double(hr), at: now)
            ZoneCueService.shared.update(hr: hr, at: now)
            zoneState = ZoneCueService.shared.state
        }
        if let phoneState = snapshot?.zoneState.flatMap(ZoneState.init(rawValue:)) {
            zoneState = phoneState
        }
        if let rower = ble.rowerData, let recorder {
            var r = recorder
            if let v = rower.strokeRate { r.add(metric: "stroke_rate", unit: "spm", source: .machine, value: v, at: now) }
            if let v = rower.instantaneousPaceSPer500m { r.add(metric: "pace_s_per_500m", unit: "s", source: .machine, value: Double(v), at: now) }
            if let v = rower.totalDistanceM { r.add(metric: "distance_m", unit: "m", source: .machine, value: Double(v), at: now) }
            if let v = rower.resistanceLevel { r.add(metric: "resistance", unit: "level", source: .machine, value: Double(v), at: now) }
            self.recorder = r
        }
    }

    static func sessionId(start: Date, type: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd-HHmm"
        return "\(f.string(from: start))-\(type)"
    }
}

struct RowView: View {
    @State private var model = RowModel()

    var body: some View {
        Group {
            if model.running {
                TabView {
                    HRPage(model: model)
                    MetricsPage(model: model)
                    Button("End", role: .destructive) { model.finish() }
                        .tint(.red)
                }
                .tabViewStyle(.page)
            } else {
                VStack(spacing: 12) {
                    Text("Rowing").font(.headline)
                    Button("Start") { model.begin() }
                        .tint(.green)
                }
            }
        }
        .navigationBarBackButtonHidden(model.running)
    }
}

private struct HRPage: View {
    let model: RowModel

    var body: some View {
        VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(model.hr.map(String.init) ?? "--")
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(color)
                Image(systemName: arrow)
                    .font(.title2)
                    .foregroundStyle(color)
            }
            Text(model.zoneName ?? "bpm")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var color: Color {
        switch model.zoneState {
        case .below: .blue
        case .inBand: .green
        case .above: .red
        case nil: .primary
        }
    }

    private var arrow: String {
        switch model.zoneState {
        case .below: "arrow.up"
        case .above: "arrow.down"
        case .inBand: "checkmark"
        case nil: "heart"
        }
    }
}

private struct MetricsPage: View {
    let model: RowModel
    private var ble: BLEManager { .shared }

    var body: some View {
        let s = model.snapshot
        let r = ble.rowerData
        let strokeRate = s?.strokeRate ?? r?.strokeRate
        let pace = (s?.pace ?? r?.instantaneousPaceSPer500m).map(Double.init)
        let distance = s?.distance ?? r?.totalDistanceM.map(Double.init)
        let resistance = (s?.resistance ?? r?.resistanceLevel).map(Double.init)
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = s?.elapsed ?? model.start.map { context.date.timeIntervalSince($0) }
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 2) {
                row("SPM", strokeRate.map { String(format: "%.0f", $0) })
                row("/500m", pace.map(Self.clock))
                row("m", distance.map { String(format: "%.0f", $0) })
                row("Res", resistance.map { String(format: "%.0f", $0) })
                row("Time", elapsed.map(Self.clock))
            }
        }
    }

    private func row(_ label: String, _ value: String?) -> some View {
        GridRow {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value ?? "--").font(.title3.monospacedDigit().bold())
        }
    }

    static func clock(_ seconds: Double) -> String {
        let s = Int(seconds)
        return s >= 3600
            ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
            : String(format: "%d:%02d", s / 60, s % 60)
    }
}
