import Foundation
import Testing
import PackFitSchemas
@testable import PackFit

struct SuggestionMatchTests {
    private func suggestion(_ name: String, _ category: PackFitSchemas.Category) -> Suggestion {
        Suggestion(id: UUID().uuidString, name: name, reason: "", category: category, estDims: [10, 5, 10], estKg: 0.2, fragile: false, soft: true, essential: false)
    }

    private func item(_ name: String, _ category: PackFitSchemas.Category) -> Item {
        var item = AppFixtures.items()[0]
        item.id = UUID().uuidString
        item.name = name
        item.category = category
        return item
    }

    @Test func scannedItemsCoverLooserNames() {
        let suggestions = [
            suggestion("Passport wallet", .documents),
            suggestion("Phone charger cable", .electronics),
            suggestion("Toiletry pouch", .toiletries),
            suggestion("Warm sweater", .clothing),
        ]
        let items = [
            item("Passport", .documents),
            item("Phone chargers and cables pouch", .electronics),
            item("Clear quart bag of travel toiletries", .toiletries),
        ]
        #expect(SuggestionMatch.open(suggestions, excluding: items).map(\.name) == ["Warm sweater"])
    }

    @Test func eachItemCoversOneRepeat() {
        let suggestions = (1...5).map { suggestion("T-shirt stack (\($0))", .clothing) }
        let items = [item("Gray cotton T-shirt", .clothing), item("Black tee", .clothing), item("White t shirts", .clothing)]
        #expect(SuggestionMatch.open(suggestions, excluding: items).map(\.name) == ["T-shirt stack (4)", "T-shirt stack (5)"])
    }

    @Test func countedItemCoversThatMany() {
        let suggestions = (1...5).map { suggestion("T-shirt stack (\($0))", .clothing) }
        #expect(SuggestionMatch.open(suggestions, excluding: [item("T-shirts x5, folded stack", .clothing)]).isEmpty)
        #expect(SuggestionMatch.open(suggestions, excluding: [item("3x tees", .clothing)]).count == 2)
        #expect(SuggestionMatch.quantity("Shampoo 250 ml") == 1)
    }

    @Test func sharedDescriptorsDoNotMatch() {
        let suggestions = [suggestion("Warm sweater", .clothing), suggestion("Travel pouch", .other)]
        let items = [item("Warm jacket", .clothing), item("Toiletry pouch", .toiletries)]
        #expect(SuggestionMatch.open(suggestions, excluding: items).count == 2)
    }

    @Test func otherCategoryNeedsEveryWord() {
        let cable = [suggestion("Phone charger cable", .electronics)]
        #expect(SuggestionMatch.open(cable, excluding: [item("HDMI cable", .other)]).count == 1)
        #expect(SuggestionMatch.open(cable, excluding: [item("Phone charger cable", .other)]).isEmpty)
    }

    @Test func headNounSkipsSizesAndContainers() {
        #expect(SuggestionMatch.headNoun("T-shirt stack (3)") == "tshirt")
        #expect(SuggestionMatch.headNoun("Hiking socks") == "sock")
        #expect(SuggestionMatch.headNoun("Travel pouch") == nil)
    }
}
