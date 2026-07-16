/*
 * Purpose: The drill sheet — renders the daily drill's prompt, a decimal-pad
 *          numeric field or choice buttons, and the graded answer state
 *          (verdict + correct value/choice + explanation + streak). Presented
 *          from TodayView's DrillCard.
 * Inputs: a DrillViewModel (engine/recorder wired by the presenter).
 * Outputs: none (grading/recording/snapshot side effects live in the VM).
 * Run: .sheet { DrillView(viewModel: drillViewModel) }
 */

import SwiftUI

struct DrillView: View {
    let viewModel: DrillViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Daily Drill")
                .navigationBarTitleDisplayMode(.inline)
        }
        .task { await viewModel.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .loading:
            ProgressView("Loading today's drill…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .ready(let drill):
            answering(drill)
        case .answered(let correct):
            answered(correct: correct)
        case .failed(let message):
            failed(message)
        }
    }

    // MARK: - Answering

    private func answering(_ drill: Drill) -> some View {
        @Bindable var viewModel = viewModel
        return VStack(alignment: .leading, spacing: 20) {
            Text(drill.prompt)
                .font(.title3)
                .fontWeight(.medium)

            switch drill.answer.kind {
            case .numeric:
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        Button {
                            viewModel.isNegative.toggle()
                        } label: {
                            Image(systemName: "plusminus")
                                .font(.title3)
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.bordered)
                        .tint(viewModel.isNegative ? .red : Color("BrandAccent"))
                        .accessibilityLabel("Toggle negative")

                        HStack(spacing: 4) {
                            if viewModel.isNegative {
                                Text("−")
                                    .font(.title2)
                                    .foregroundStyle(.red)
                                    .accessibilityHidden(true)
                            }
                            TextField("Your answer", text: $viewModel.numericInput)
                                .keyboardType(.decimalPad)
                                .textFieldStyle(.roundedBorder)
                                .font(.title2)
                        }
                    }
                    Text("Enter a number. Tap ± for a negative answer.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            case .choice:
                VStack(spacing: 10) {
                    ForEach(Array((drill.choices ?? []).enumerated()), id: \.offset) { index, choice in
                        choiceButton(choice, index: index)
                    }
                }
            }

            Spacer()

            Button {
                Task { await viewModel.submit() }
            } label: {
                Text("Submit")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color("BrandAccent"))
            .controlSize(.large)
            .disabled(!canSubmit(drill))
        }
        .padding()
    }

    private func choiceButton(_ choice: String, index: Int) -> some View {
        let selected = viewModel.selectedChoice == index
        return Button {
            viewModel.selectedChoice = index
        } label: {
            HStack {
                Text(choice)
                    .multilineTextAlignment(.leading)
                Spacer()
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Color("BrandAccent").opacity(0.15) : Color(.secondarySystemBackground))
            .foregroundStyle(selected ? Color("BrandAccent") : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private func canSubmit(_ drill: Drill) -> Bool {
        switch drill.answer.kind {
        case .numeric:
            return Double(viewModel.numericInput) != nil
        case .choice:
            return viewModel.selectedChoice != nil
        }
    }

    // MARK: - Answered

    @ViewBuilder
    private func answered(correct: Bool) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 8) {
                Image(systemName: correct ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(correct ? Color("BrandAccent") : .red)
                Text(correct ? "Correct" : "Not quite")
                    .font(.title2)
                    .fontWeight(.semibold)
            }

            if let drill = viewModel.drill {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Answer")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(correctAnswerText(drill))
                        .font(.headline)
                }
                Text(drill.explanation)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                Image(systemName: "flame")
                    .foregroundStyle(Color("BrandAccent"))
                Text(viewModel.streakDays == 1 ? "1 day streak" : "\(viewModel.streakDays) day streak")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Text("Done")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color("BrandAccent"))
            .controlSize(.large)
        }
        .padding()
    }

    private func correctAnswerText(_ drill: Drill) -> String {
        switch drill.answer.kind {
        case .numeric:
            if let value = drill.answer.value { return value.formatted() }
            return "—"
        case .choice:
            if let index = drill.answer.correctIndex, let choices = drill.choices,
               choices.indices.contains(index) {
                return choices[index]
            }
            return "—"
        }
    }

    // MARK: - Failed

    private func failed(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.slash")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Retry") {
                Task { await viewModel.load() }
            }
            .buttonStyle(.borderedProminent)
            .tint(Color("BrandAccent"))
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
