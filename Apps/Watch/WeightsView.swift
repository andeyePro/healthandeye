import SwiftUI
import HealthAndICore

@MainActor @Observable
final class WeightsModel {
    /// Shared so the bridge callback outlives any one view instance.
    static let shared = WeightsModel()

    private(set) var session: Session?
    let rest = RestTimer()

    private var store: StoreController { .shared }
    private var bridge: WatchBridge { .shared }

    var exercises: [Exercise] {
        let mine = store.catalogue.exercises.filter(\.enabled)
        return mine.isEmpty ? StarterPack.load().exercises.filter(\.enabled) : mine
    }

    var effortScale: EffortScale { store.catalogue.settings.effortScale }

    private init() {
        bridge.onWeightsLink = { [weak self] link in self?.follow(link) }
        if let link = bridge.weightsLink { follow(link) }
    }

    private var link: WeightsLink? {
        session.map { WeightsLink(sessionId: $0.id, start: $0.start, active: true) }
    }

    /// The watch generates the id the phone would, and the phone adopts it.
    func startSession() {
        let now = Date()
        session = Session(id: RowModel.sessionId(start: now, type: "weights"), start: now, type: "weights",
                          hrSource: .appleWatch)
        rest.stop()
        if let link { bridge.send(command: .startSession, link: link) }
    }

    /// Joins the phone's session, or closes ours when the phone finishes it. A watch session that already
    /// has sets is kept: the phone appends those sets to its own session as they arrive.
    private func follow(_ phone: WeightsLink) {
        if phone.active {
            guard Date().timeIntervalSince(phone.start) < 12 * 3600 else { return }
            if session == nil || (session?.id != phone.sessionId && session?.sets.isEmpty == true) {
                session = Session(id: phone.sessionId, start: phone.start, type: "weights")
                rest.stop()
            }
        } else if session?.id == phone.sessionId {
            finishSession(notifyPhone: false)
        }
    }

    func log(exercise: Exercise, side: Side, reps: Int, effort: Double) {
        if session == nil { startSession() }
        guard var current = session else { return }
        let now = Date()
        var entry = SetEntry(
            id: "\(current.id)-set-\(current.sets.count + 1)",
            exerciseId: exercise.id,
            side: exercise.unilateral ? side : .both,
            reps: reps,
            rir: effortScale == .rir ? effort : nil,
            rpe: effortScale == .rpe ? effort : nil,
            timestamp: now)
        rest.apply(to: &entry)
        current.sets.append(entry)
        session = current
        bridge.send(set: entry, link: WeightsLink(sessionId: current.id, start: current.start, active: true))
        Haptics.play(.up)
        rest.start(for: exercise)
    }

    /// Everything goes by transferUserInfo, which queues while out of range and delivers on reconnect;
    /// the local copy is kept only when the phone cannot be reached now.
    func finishSession(notifyPhone: Bool = true) {
        guard var current = session else { return }
        current.end = .now
        rest.stop()
        if notifyPhone, let link { bridge.send(command: .stopSession, link: link) }
        if !current.sets.isEmpty {
            bridge.send(session: current)
            if !bridge.isReachable {
                store.saveSession(current)
            }
        }
        session = nil
    }
}

struct WeightsView: View {
    @State private var model = WeightsModel.shared
    @State private var exerciseId: String?
    @State private var side: Side = .left
    @State private var crown: Double = 8
    @State private var effort: Double = 2

    private var reps: Int { max(0, Int(crown.rounded())) }

    var body: some View {
        let exercises = model.exercises
        let exercise = exercises.first { $0.id == exerciseId } ?? exercises.first
        ScrollView {
            VStack(spacing: 8) {
                if exercises.isEmpty {
                    Text("No exercises").foregroundStyle(.secondary)
                } else {
                    Picker("Exercise", selection: Binding(
                        get: { exercise?.id ?? "" },
                        set: { exerciseId = $0 })) {
                        ForEach(exercises) { Text($0.name).tag($0.id) }
                    }
                    .frame(height: 50)
                }

                if exercise?.unilateral == true {
                    Picker("Side", selection: $side) {
                        Text("L").tag(Side.left)
                        Text("R").tag(Side.right)
                    }
                    .pickerStyle(.navigationLink)
                }

                Text("\(reps)")
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .focusable()
                    .digitalCrownRotation($crown, from: 0, through: 100, by: 1, sensitivity: .medium,
                                          isContinuous: false, isHapticFeedbackEnabled: true)
                Text("reps").font(.caption2).foregroundStyle(.secondary)

                Picker(model.effortScale == .rir ? "RIR" : "RPE", selection: $effort) {
                    ForEach(effortValues, id: \.self) { v in
                        Text(v.formatted(.number.precision(.fractionLength(0...1)))).tag(v)
                    }
                }
                .frame(height: 50)

                if model.rest.isRunning {
                    Text(Duration.seconds(model.rest.remaining.rounded(.up)), format: .time(pattern: .minuteSecond))
                        .font(.title3.monospacedDigit())
                        .foregroundStyle(model.rest.hasFinished ? .green : .orange)
                }

                Button("Log set") {
                    if let exercise {
                        model.log(exercise: exercise, side: side, reps: reps, effort: effort)
                        if exercise.unilateral { side = side == .left ? .right : .left }
                    }
                }
                .tint(.green)
                .disabled(exercise == nil)

                if let s = model.session {
                    Text("\(s.sets.count) sets").font(.footnote).foregroundStyle(.secondary)
                    Button("Finish session", role: .destructive) { model.finishSession() }
                } else {
                    Button("Start session") { model.startSession() }
                }
            }
        }
        .navigationTitle("Weights")
        .onChange(of: model.effortScale, initial: true) { _, scale in
            effort = scale == .rir ? 2 : 8
        }
    }

    private var effortValues: [Double] {
        let range: ClosedRange<Double> = model.effortScale == .rir ? 0...5 : 5...10
        return stride(from: range.lowerBound, through: range.upperBound, by: 0.5).map { $0 }
    }
}
