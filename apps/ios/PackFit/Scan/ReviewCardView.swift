import SwiftUI

struct ReviewCardView: View {
    @State var item: Item
    let alternatives: [ItemAlternative]
    let onSave: (Item) -> Void
    let onCancel: () -> Void

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
                        onSave(item)
                    }
                }
            }
        }
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
