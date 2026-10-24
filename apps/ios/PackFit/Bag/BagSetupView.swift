import SwiftUI

struct BagSetupView: View {
    @Environment(TripStore.self) private var tripStore
    @Environment(DeviceCapabilities.self) private var caps
    @Binding var path: [Route]

    @State private var showManual = false
    @State private var showWheels = false
    @State private var pendingBag: Container?
    @State private var showBackpackEditor = false

    private let wallInsetCm: Double = 3

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
                if caps.hasLidar && !caps.isSimulator {
                    Button(Copy.Bag.measureLidar) {
                        // Demo path: seed a LiDAR-measured checked bag quickly.
                        pendingBag = makeCustom(outer: [75, 50, 30], method: .lidar, confidence: 0.92)
                        showWheels = true
                    }
                }
                Button(Copy.Bag.measureManual) { showManual = true }
            }
        }
        .navigationTitle(Copy.Bag.title)
        .sheet(isPresented: $showManual) {
            ManualBagView { outer, limit in
                pendingBag = makeCustom(outer: outer, method: .manual, confidence: 1, weightLimit: limit)
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

    private func makeCustom(
        outer: [Double],
        method: MeasureMethod,
        confidence: Double,
        weightLimit: Double = 23
    ) -> Container {
        let inner = outer.map { max(1, $0 - wallInsetCm * 2) }
        // Keep height inset consistent with "3 cm per side".
        return Container(
            id: UUID().uuidString,
            name: "Custom bag",
            type: .suitcase,
            outer: outer,
            compartments: [Compartment(name: "main", dims: inner, compressibility: 0.1)],
            weightLimitKg: weightLimit,
            wheelsSide: .bottom,
            measurement: Measurement(method: method, confidence: confidence, deviceHasLidar: method == .lidar)
        )
    }

    private func dimsLabel(_ outer: [Double]) -> String {
        String(format: "%.0f×%.0f×%.0f cm", outer[0], outer[1], outer[2])
    }
}
