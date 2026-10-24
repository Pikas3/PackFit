import SwiftUI

struct ReviewCardView: View {
    @State var item: Item
    let alternatives: [ItemAlternative]
    let onSave: (Item) -> Void
    let onCancel: () -> Void
    /// The size as measured, to tell when the user corrected it.
    private let measured: [Double]

    init(item: Item, alternatives: [ItemAlternative], onSave: @escaping (Item) -> Void, onCancel: @escaping () -> Void) {
        _item = State(initialValue: item)
        self.alternatives = alternatives
        self.onSave = onSave
        self.onCancel = onCancel
        measured = [item.w, item.h, item.d]
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        MeasurementMethodBadge(method: item.measurement?.method)
                        ConfidenceBadge(confidence: item.measurement?.confidence ?? item.confidence)
                    }
                }
                Section("Identity") {
                    TextField("Name", text: $item.name)
                        .onSubmit { fillFromCatalog(name: item.name) }
                    Picker("Category", selection: $item.category) {
                        ForEach(Category.allCases, id: \.self) { cat in
                            Text(cat.rawValue.capitalized).tag(cat)
                        }
                    }
                    if !alternatives.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(alternatives, id: \.self) { alt in
                                    Button(alt.name) {
                                        item.name = alt.name
                                        item.category = alt.category
                                        fillFromCatalog(name: alt.name)
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                        }
                    }
                }
                Section("Size & weight") {
                    dimField("Width", value: $item.w)
                    dimField("Height", value: $item.h)
                    dimField("Depth", value: $item.d)
                    dimField("kg", value: $item.kg)
                }
                Section("Flags") {
                    Toggle("Fragile", isOn: $item.fragile)
                    Toggle("Soft", isOn: $item.soft)
                    Toggle("Keep upright", isOn: $item.upright)
                    Toggle("Needed at security", isOn: Binding(
                        get: { item.neededAtSecurity ?? false },
                        set: { item.neededAtSecurity = $0 }
                    ))
                    Slider(value: $item.hardness, in: 0...1)
                    Text("Hardness \(item.hardness, specifier: "%.2f")")
                        .font(Tokens.TypeScale.caption)
                }
            }
            .navigationTitle("Review")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(Copy.Scan.save) {
                        item.source = .scan
                        // A corrected size is the user's own measurement: no padding for it.
                        if zip([item.w, item.h, item.d], measured).contains(where: { abs($0 - $1) > 0.05 }) {
                            item.measurement = Measurement(method: .manual, confidence: 1, deviceHasLidar: item.measurement?.deviceHasLidar ?? false)
                        }
                        onSave(item)
                    }
                }
            }
        }
    }

    /// A new name brings that kind of item's weight and handling with it. The size stays
    /// as measured (rule 6), and every field can still be changed after.
    private func fillFromCatalog(name: String) {
        let catalog = TravelCatalog.shared
        guard let entry = catalog.rank(name: name).first(where: { $0.score >= 0.8 })?.entry else { return }
        item.category = entry.category
        item.kg = catalog.kg(for: entry, dimsCm: [item.w, item.h, item.d])
        item.fragile = entry.fragile
        item.soft = entry.soft
        item.hardness = entry.hardness
        item.upright = entry.upright
        item.neededAtSecurity = entry.neededAtSecurity ? true : nil
    }

    private func dimField(_ title: String, value: Binding<Double>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField(
                title,
                value: value,
                format: .number.precision(.fractionLength(1))
            )
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .frame(width: 90)
        }
    }
}
