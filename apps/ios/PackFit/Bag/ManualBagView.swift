import SwiftUI
import RealityKit
import UIKit

struct ManualBagView: View {
    let onSave: ([Double], Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var w = "75"
    @State private var h = "50"
    @State private var d = "30"
    @State private var limit = "23"

    var body: some View {
        NavigationStack {
            VStack(spacing: Tokens.Spacing.md) {
                Form {
                    Section("Outer dimensions (cm)") {
                        TextField("Width", text: $w).keyboardType(.decimalPad)
                        TextField("Height", text: $h).keyboardType(.decimalPad)
                        TextField("Depth", text: $d).keyboardType(.decimalPad)
                    }
                    Section(Copy.Bag.weightLimit) {
                        TextField("kg", text: $limit).keyboardType(.decimalPad)
                    }
                }
                .frame(maxHeight: 280)

                RealityView { content in
                    let size = previewSize
                    let box = ModelEntity(
                        mesh: .generateBox(size: size),
                        materials: [SimpleMaterial(color: UIColor.cyan.withAlphaComponent(0.35), isMetallic: false)]
                    )
                    content.add(box)
                    let cam = PerspectiveCamera()
                    cam.position = [size.x + 0.4, size.y + 0.3, size.z + 0.6]
                    cam.look(at: .zero, from: cam.position, relativeTo: nil)
                    content.add(cam)
                }
                .id("\(w)-\(h)-\(d)")
                .frame(height: 220)
                .background(Color.black.opacity(0.06), in: RoundedRectangle(cornerRadius: Tokens.Radius.md))
                .padding(.horizontal)
            }
            .navigationTitle(Copy.Bag.measureManual)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use bag") {
                        onSave(
                            [Double(w) ?? 75, Double(h) ?? 50, Double(d) ?? 30],
                            Double(limit) ?? 23
                        )
                    }
                }
            }
        }
    }

    private var previewSize: SIMD3<Float> {
        let cw = max(0.05, Float(Double(w) ?? 75) * 0.01)
        let ch = max(0.05, Float(Double(h) ?? 50) * 0.01)
        let cd = max(0.05, Float(Double(d) ?? 30) * 0.01)
        return [cw, ch, cd]
    }
}
