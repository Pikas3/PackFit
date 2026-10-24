import SwiftUI

/// Step label, Play/Pause and the step slider. Used by the 3D viewer and the AR overlay.
struct PlanStepControls: View {
    let stepper: PlanStepper
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
            HStack {
                Text("\(Copy.Viewer.step) \(stepper.currentStep)/\(stepper.stepCount)")
                    .font(Tokens.TypeScale.callout)
                Spacer()
                Button(stepper.isPlaying ? Copy.Viewer.pause : Copy.Viewer.play) {
                    stepper.togglePlay(reduceMotion: reduceMotion)
                }
                .buttonStyle(.borderedProminent)
                .tint(Tokens.Color.brand)
                .disabled(stepper.stepCount == 0)
            }
            Slider(
                value: Binding(
                    get: { Double(stepper.currentStep) },
                    set: { stepper.goToStep(Int($0.rounded()), animated: !reduceMotion) }
                ),
                in: 0...Double(max(stepper.stepCount, 1)),
                step: 1
            )
            if let item = stepper.currentItem {
                Text(item.name)
                    .font(Tokens.TypeScale.title)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
