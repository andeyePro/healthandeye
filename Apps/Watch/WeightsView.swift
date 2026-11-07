import SwiftUI
import HealthAndICore

@MainActor @Observable
final class WeightsModel {
    private(set) var session: Session?
    let rest = RestTimer()

    private var store: StoreController { .shared }
    private var bridge: WatchBridge { .shared }

    var exercises: [Exercise] {
        let mine = store.catalogue.exercises.filter(\.enabled)
        return mine.isEmpty ? StarterPack.load().exercises.filter(\.enabled) : mine
    }

    var effortScale: EffortScale { store.catalogue.settings.effortScale }

    func startSession() {
        let now = Date()
        session = Session(id: RowModel.sessionId(start: now, type: "weights"), start: now, type: "weights")
        rest.stop()
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
        bridge.send(set: entry)
        Haptics.play(.up)
        rest.start(for: exercise)
    }

    func finishSession() {
        guard var current = session else { return }
        current.end = .now
        rest.stop()
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
    @State private var model = WeightsModel()
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
