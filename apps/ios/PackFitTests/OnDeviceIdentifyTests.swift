import Foundation
import Testing
@testable import PackFit

struct OnDeviceIdentifyTests {
    let catalog = TravelCatalog.shared

    @Test func catalogLoads() {
        #expect(catalog.entries.count >= 50)
        #expect(Set(catalog.entries.map(\.id)).count == catalog.entries.count)
    }

    @Test func visionLabelsPickTheItem() throws {
        let top = try #require(catalog.rank(labels: [("running_shoe", 0.6), ("footwear", 0.3)], dimsCm: [30, 11, 12]).first)
        #expect(top.entry.category == .shoes)
    }

    @Test func sizeSeparatesLookAlikes() throws {
        // Vision often says "computer" for both; a 32 × 22 × 1.6 cm slab is the laptop.
        let labels: [(String, Double)] = [("computer", 0.5), ("book", 0.4)]
        let laptop = try #require(catalog.rank(labels: labels, dimsCm: [32, 1.6, 22]).first)
        #expect(laptop.entry.id == "laptop")
    }

    @Test func typedNameFindsEntry() throws {
        let top = try #require(catalog.rank(name: "my blue hoodie").first)
        #expect(top.entry.id == "sweater")
        #expect(catalog.rank(name: "Pocket knife").first?.entry.category == .sharp)
    }

    @Test func clothesWeightScalesWithSize() throws {
        let tee = try #require(catalog.entries.first { $0.id == "tshirt" })
        #expect(catalog.kg(for: tee, dimsCm: [28, 22, 9]) > tee.kg)
        let laptop = try #require(catalog.entries.first { $0.id == "laptop" })
        #expect(catalog.kg(for: laptop, dimsCm: [40, 30, 3]) == laptop.kg)
    }

    @Test func knifeIsBannedInCarryOnOnly() throws {
        let trip = try #require(AppFixtures.trips().first)
        let knife = Item(id: "k", name: "Pocket knife", w: 10, h: 2, d: 3, kg: 0.1, category: .sharp)
        let carry = LocalRules.shared.flags(for: [knife], trip: trip, bag: "carryOn")
        #expect(carry.contains { $0.ruleId == "tsa:pocket-knife" && $0.severity == .banned })
        #expect(carry.allSatisfy { $0.sourceUrl.hasPrefix("https://") })
        #expect(LocalRules.shared.flags(for: [knife], trip: trip, bag: "checked").isEmpty)
    }

    @Test func laptopIsNotFlaggedAsASpareBattery() throws {
        let trip = try #require(AppFixtures.trips().first)
        let laptop = Item(id: "l", name: "Laptop", w: 30, h: 2, d: 21, kg: 1.3, category: .electronics)
        let flags = LocalRules.shared.flags(for: [laptop], trip: trip, bag: "checked")
        #expect(!flags.contains { $0.ruleId == "tsa:lithium-battery-spare" })
    }

    @Test func powerBankBannedInChecked() throws {
        let trip = try #require(AppFixtures.trips().first)
        let bank = Item(id: "p", name: "Power bank", w: 14, h: 2.5, d: 7, kg: 0.3, category: .electronics)
        let flags = LocalRules.shared.flags(for: [bank], trip: trip, bag: "checked")
        #expect(flags.contains { $0.ruleId == "tsa:lithium-battery-spare" && $0.severity == .banned })
    }
}
