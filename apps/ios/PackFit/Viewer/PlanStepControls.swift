import SwiftUI

/// Step label, Play/Pause and the step slider. Used by the 3D viewer and the AR overlay.
struct PlanStepControls: View {
    let stepper: PlanStepper
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private typealias P = Tokens.Palette
    private typealias T = Tokens.TypeScale

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(Copy.Viewer.step) \(stepper.currentStep)/\(stepper.stepCount)")
                        .eyebrow(P.pink700)
                    Text(stepper.currentItem?.name ?? " ")
                        .font(T.h3)
                        .foregroundStyle(P.textPrimary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    stepper.togglePlay(reduceMotion: reduceMotion)
                } label: {
                    Image(systemName: stepper.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(P.pink800)
                        .frame(width: 44, height: 44)
                        .background(P.pink300, in: Circle())
                        .shadow(color: P.buttonShadow, radius: 6, y: 4)
                }
                .buttonStyle(.plain)
                .disabled(stepper.stepCount == 0)
                .accessibilityLabel(stepper.isPlaying ? Copy.Viewer.pause : Copy.Viewer.play)
            }
            Slider(
                value: Binding(
                    get: { Double(stepper.currentStep) },
                    set: { stepper.goToStep(Int($0.rounded()), animated: !reduceMotion) }
                ),
                in: 0...Double(max(stepper.stepCount, 1)),
                step: 1
            )
            .tint(P.pink700)
            .accessibilityLabel(Copy.Viewer.step)
            if stepper.currentItem != nil {
                let notes = stepper.currentNotes
                if !notes.isEmpty {
                    Text(notes.joined(separator: " · ").capitalizedFirst)
                        .font(T.caption)
                        .foregroundStyle(P.textSecondary)
                }
            }
        }
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
