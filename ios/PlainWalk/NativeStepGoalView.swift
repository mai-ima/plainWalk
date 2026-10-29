import SwiftUI

@MainActor struct NativeStepGoalView: View {
    @ObservedObject var model: NativeAppModel
    @State private var goal: Double
    @State private var enabled: Bool
    @State private var saving = false

    init(model: NativeAppModel) {
        self.model = model
        let saved = nativeNumber(model.config["goal"]) ?? 5000
        _goal = State(initialValue: min(100_000, max(100, saved.rounded())))
        _enabled = State(initialValue: model.config["goalEnabled"] as? Bool ?? false)
    }

    private var todaySteps: Double? {
        guard let steps = model.todaySteps, steps.isFinite, steps >= 0 else { return nil }
        return steps.rounded(.down)
    }
    private var progress: Double { min(1, max(0, (todaySteps ?? 0) / goal)) }
    private var goalText: String { goal.formatted(.number.precision(.fractionLength(0))) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    todayCard
                }
                Section {
                    Toggle("歩数の目標を使う", isOn: $enabled).tint(.green).frame(minHeight: 44)
                } footer: {
                    Text("目標を決めて、今日の歩数と見比べられます。")
                }
                Section("1日の歩数の目標") {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Text(goal, format: .number.precision(.fractionLength(0)))
                                .font(.largeTitle.weight(.semibold)).monospacedDigit()
                            Text("歩").font(.body).foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("1日の目標、\(goalText)歩")

                        Slider(value: $goal, in: 100...100_000, step: 100)
                            .tint(.primary).frame(minHeight: 44)
                            .accessibilityLabel("目標の歩数")
                            .accessibilityValue("\(goalText)歩")

                        Stepper(value: $goal, in: 100...100_000, step: 100) {
                            Text("100歩ずつ調整").fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(minHeight: 44)
                        .accessibilityValue("\(goalText)歩")

                        Menu {
                            ForEach([3000, 5000, 8000, 10_000, 15_000, 20_000], id: \.self) { value in
                                Button("\(value.formatted())歩") { goal = Double(value) }
                            }
                        } label: {
                            Label("目標を選ぶ", systemImage: "list.bullet")
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                    }
                    .padding(.vertical, 10)
                    .disabled(!enabled)
                }
                Section {
                    Button { model.refreshSteps() } label: {
                        Label("今日の歩数を再取得", systemImage: "arrow.clockwise")
                            .frame(minHeight: 44)
                    }
                } footer: {
                    Text("歩数は端末のモーション、または許可したヘルスケアから取得します。取得できないときは「—」と表示します。")
                }
            }
            .navigationTitle("1日の歩数の目標")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル", action: model.closeSheet).disabled(saving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", action: save).fontWeight(.semibold).disabled(saving)
                }
            }
            .task { model.refreshSteps() }
        }
    }

    private var todayCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("今日の歩数", systemImage: "figure.walk").font(.subheadline).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                if let steps = todaySteps {
                    Text(steps, format: .number.precision(.fractionLength(0)))
                        .font(.largeTitle.weight(.semibold)).monospacedDigit()
                } else {
                    Text("—").font(.largeTitle.weight(.semibold)).accessibilityLabel("歩数を取得できていません")
                }
                Text("歩").foregroundStyle(.secondary)
            }
            if let steps = todaySteps, enabled {
                ProgressView(value: progress)
                    .tint(.primary)
                    .accessibilityLabel("目標の達成率")
                    .accessibilityValue("\(Int(progress * 100))パーセント")
                Text(steps >= goal ? "目標の\(goalText)歩に届きました。" : "目標の\(goalText)歩まで、あと\(max(0, goal - steps).formatted(.number.precision(.fractionLength(0))))歩。")
                    .font(.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if todaySteps != nil {
                Text("目標をオンにすると、今日の歩数と進み具合を見比べられます。")
                    .font(.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("歩数を取得すると、目標に対する進み具合がわかります。")
                    .font(.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 12)
    }

    private func save() {
        guard !saving else { return }
        saving = true
        defer { saving = false }
        var next = model.config
        let value = min(100_000, max(100, goal.rounded()))
        next["goal"] = value
        next["goalEnabled"] = enabled
        // Save both preferences together and preserve every unrelated configuration field.
        model.errorMessage = nil
        model.saveConfig(next)
        guard model.errorMessage == nil,
              nativeNumber(model.config["goal"]) == value,
              (model.config["goalEnabled"] as? Bool) == enabled else { return }
        model.closeSheet()
    }
}
