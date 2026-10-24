import SwiftUI

struct BagSetupView: View {
    @Environment(TripStore.self) private var tripStore
    @Environment(DeviceCapabilities.self) private var caps
    @Binding var path: [Route]

    @State private var showManual = false
    @State private var showWheels = false
    @State private var pendingBag: Container?
    @State private var showBackpackEditor = false

    var body: some View {
        List {
            Section(Copy.Bag.presets) {
                ForEach(AppFixtures.containers()) { bag in
                    Button {
                        if bag.type == .backpack {
                            pendingBag = bag
                            showBackpackEditor = true
                        } else {
                            tripStore.setBag(bag)
                            path.append(.itemList)
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
                            Text(bag.name)
                                .font(Tokens.TypeScale.title)
                                .foregroundStyle(.primary)
                            Text(dimsLabel(bag.outer) + " · \(Int(bag.weightLimitKg)) kg")
                                .font(Tokens.TypeScale.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section(Copy.Bag.custom) {
                if caps.supportsGuidedScan {
                    Button(Copy.Bag.measureLidar) { path.append(.guidedScan) }
                }
                Button(Copy.Bag.measureManual) { showManual = true }
            }
        }
        .navigationTitle(Copy.Bag.title)
        .sheet(isPresented: $showManual) {
            ManualBagView { outer, limit in
                pendingBag = ContainerFactory.custom(outer: outer, method: .manual, confidence: 1, weightLimit: limit)
                showManual = false
                showWheels = true
            }
        }
        .confirmationDialog(Copy.Bag.wheelsPrompt, isPresented: $showWheels, titleVisibility: .visible) {
            Button(Copy.Bag.wheelsBack) { finishWheels(.back) }
            Button(Copy.Bag.wheelsBottom) { finishWheels(.bottom) }
        }
        .sheet(isPresented: $showBackpackEditor) {
            if let bag = pendingBag {
                BackpackEditorView(bag: bag) { edited in
                    tripStore.setBag(edited)
                    showBackpackEditor = false
                    path.append(.itemList)
                }
            }
        }
    }

    private func finishWheels(_ side: WheelsSide) {
        guard var bag = pendingBag else { return }
        bag.wheelsSide = side
        tripStore.setBag(bag)
        path.append(.itemList)
    }

    private func dimsLabel(_ outer: [Double]) -> String {
        String(format: "%.0f×%.0f×%.0f cm", outer[0], outer[1], outer[2])
    }
}
