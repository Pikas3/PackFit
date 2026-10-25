import SwiftUI

struct BackpackEditorView: View {
    @State var bag: Container
    let onSave: (Container) -> Void
    @Environment(\.dismiss) private var dismiss

    private let presets = ["main", "front", "laptop"]

    var body: some View {
        NavigationStack {
            List {
                Section("Compartments") {
                    ForEach(bag.compartments.indices, id: \.self) { index in
                        VStack(alignment: .leading) {
                            TextField("Name", text: bindingName(index))
                            Text(String(
                                format: "%.0f×%.0f×%.0f",
                                bag.compartments[index].dims[0],
                                bag.compartments[index].dims[1],
                                bag.compartments[index].dims[2]
                            ))
                            .font(Tokens.TypeScale.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { bag.compartments.remove(atOffsets: $0) }
                }
                Section("Add preset region") {
                    ForEach(presets, id: \.self) { name in
                        Button(name.capitalized) {
                            guard !bag.compartments.contains(where: { $0.name == name }) else { return }
                            let outer = bag.outer
                            let dims: [Double]
                            switch name {
                            case "front": dims = [outer[0] - 4, outer[1] * 0.6, 6]
                            case "laptop": dims = [outer[0] - 4, outer[1] - 8, 3]
                            default: dims = [outer[0] - 2, outer[1] - 4, outer[2] - 2]
                            }
                            bag.compartments.append(Compartment(name: name, dims: dims, compressibility: name == "laptop" ? 0 : 0.15))
                        }
                    }
                }
            }
            .snuglyCanvas()
            .navigationTitle("Backpack")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(Copy.Bag.continueItems) { onSave(bag) }
                }
            }
        }
    }

    private func bindingName(_ index: Int) -> Binding<String> {
        Binding(
            get: { bag.compartments[index].name },
            set: { bag.compartments[index].name = $0 }
        )
    }
}
