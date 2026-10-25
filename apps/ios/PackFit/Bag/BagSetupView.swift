import SwiftUI

struct BagSetupView: View {
    @Environment(TripStore.self) private var tripStore
    @Environment(DeviceCapabilities.self) private var caps
    @Binding var path: [Route]

    @State private var showManual = false
    @State private var showWheels = false
    @State private var showShell = false
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
                        } else if bag.type == .suitcase {
                            pendingBag = bag
                            showShell = true
                        } else {
                            tripStore.setBag(bag)
                            path.append(.itemList)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            IconBubble(systemImage: bag.type == .backpack ? "backpack" : "suitcase.rolling")
                            VStack(alignment: .leading, spacing: 2) {
                                Text(bag.name)
                                    .font(Tokens.TypeScale.h3)
                                    .foregroundStyle(Tokens.Palette.textPrimary)
                                Text(dimsLabel(bag.outer) + " · \(Int(bag.weightLimitKg)) kg")
                                    .font(Tokens.TypeScale.caption)
                                    .foregroundStyle(Tokens.Palette.textSecondary)
                            }
                            Spacer()
                            if tripStore.bag?.id == bag.id
                                || (tripStore.bag?.name.hasPrefix(bag.name) == true
                                    && tripStore.bag?.type == bag.type) {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(Tokens.Palette.green600)
                            }
                        }
                    }
                }
            }
            Section(Copy.Bag.custom) {
                if caps.supportsGuidedScan {
                    Button { path.append(.guidedScan) } label: {
                        Label(Copy.Bag.measureLidar, systemImage: "camera.metering.matrix")
                    }
                }
                Button { showManual = true } label: {
                    Label(Copy.Bag.measureManual, systemImage: "ruler")
                }
            }
        }
        .packFitCanvas()
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
        .confirmationDialog(Copy.Bag.shellPrompt, isPresented: $showShell, titleVisibility: .visible) {
            Button(Copy.Bag.shellSingle) { finishShell(.single) }
            Button(Copy.Bag.shellTwoSided) { finishShell(.twoSided) }
        } message: {
            Text(Copy.Bag.shellMessage)
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
        pendingBag = bag
        if bag.type == .suitcase {
            showShell = true
        } else {
            tripStore.setBag(bag)
            path.append(.itemList)
        }
    }

    private func finishShell(_ shell: SuitcaseShell) {
        guard let bag = pendingBag else { return }
        tripStore.setBag(ContainerFactory.applying(shell, to: bag))
        pendingBag = nil
        path.append(.itemList)
    }

    private func dimsLabel(_ outer: [Double]) -> String {
        String(format: "%.0f×%.0f×%.0f cm", outer[0], outer[1], outer[2])
    }
}
