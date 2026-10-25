import Foundation

@Observable
@MainActor
final class ItemsStore {
    var items: [Item] = []
    /// Solids from the photo scan (box, standing or lying cylinder), used to pick each
    /// item's 3D model. App-only: not in the schema, never sent to the server or the packer.
    var shapes: [String: ObjectShape] = [:]

    func append(_ item: Item) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
        } else {
            items.append(item)
        }
    }

    func update(_ item: Item) {
        append(item)
    }

    func remove(id: String) {
        items.removeAll { $0.id == id }
    }

    func remove(at offsets: IndexSet) {
        items.remove(atOffsets: offsets)
    }

    /// Seeds the first three fixture items for a cold demo if needed.
    func loadDemoSeed() {
        items = Array(AppFixtures.items().prefix(3))
    }
}
