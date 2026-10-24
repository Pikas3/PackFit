import PackFitSchemas
import Testing
@testable import Packer

@Suite struct DescribeTests {
    // 60 x 30 x 40 suitcase. Thirds: x 0-20-40-60, z 0-13.3-26.7-40.
    let items = [
        item("Jeans", 60, 5, 40, kg: 0.6, hardness: 0.1),
        item("Mug", 10, 10, 10, kg: 0.3, hardness: 1, fragile: true),
        item("Shoes", 20, 10, 12, kg: 0.6),
        item("Passport", 12, 1, 9, kg: 0.05, security: true),
    ]
    var p: Plan {
        plan([
            place("Jeans", 0, 0, 0, 60, 5, 40, order: 0),
            place("Mug", 0, 5, 0, 10, 10, 10, order: 1),        // back left
            place("Shoes", 40, 5, 28, 20, 10, 12, order: 2),    // front right
            place("Passport", 24, 5, 15, 12, 1, 9, order: 3),   // centre
        ])
    }

    @Test func regionsAndPositions() throws {
        let jeans = try #require(describeStep(p, items: items, order: 0, container: suitcase))
        #expect(jeans.position == .bottom)
        #expect(jeans.region == "across the whole bag")
        #expect(jeans.near == [])

        let mug = try #require(describeStep(p, items: items, order: 1, container: suitcase))
        #expect(mug.region == "back left corner")
        #expect(mug.position == .middle)
        #expect(mug.near == ["Jeans"])
        #expect(mug.notes == ["fragile, nothing goes on top"])

        let shoes = try #require(describeStep(p, items: items, order: 2, container: suitcase))
        #expect(shoes.region == "front right corner")
        #expect(shoes.near == ["Jeans"])

        let passport = try #require(describeStep(p, items: items, order: 3, container: suitcase))
        #expect(passport.region == "centre")
        #expect(passport.notes == ["keep accessible for security"])
    }

    @Test func neighboursAreOnlyEarlierTouchingItems() throws {
        let placed = plan([
            place("Jeans", 0, 0, 0, 60, 5, 40, order: 0),
            place("Shoes", 0, 5, 0, 20, 10, 12, order: 1),
            place("Mug", 20, 5, 0, 10, 10, 10, order: 2),       // touches Shoes' right face
            place("Passport", 50, 5, 30, 10, 1, 9, order: 3),   // touches only Jeans
        ])
        #expect(try #require(describeStep(placed, items: items, order: 2, container: suitcase)).near == ["Jeans", "Shoes"])
        #expect(try #require(describeStep(placed, items: items, order: 3, container: suitcase)).near == ["Jeans"])
        #expect(try #require(describeStep(placed, items: items, order: 1, container: suitcase)).near == ["Jeans"])
    }

    @Test func topAndCompartmentNotes() throws {
        let stack = plan([
            place("Jeans", 0, 0, 0, 60, 5, 40, order: 0),
            place("Shoes", 0, 5, 0, 20, 20, 12, order: 1),
        ])
        #expect(try #require(describeStep(stack, items: items, order: 1, container: suitcase)).position == .top)

        let laptop = [item("Laptop", 30, 1, 21, kg: 1.2, hardness: 0.9, category: .electronics)]
        let inSleeve = plan([place("Laptop", 0, 0, 0, 21, 30, 1, order: 0, in: "laptop")])
        let step = try #require(describeStep(inSleeve, items: laptop, order: 0, container: backpack))
        #expect(step.notes == ["goes in the laptop compartment"])
    }

    @Test func missingStepIsNil() {
        #expect(describeStep(p, items: items, order: 99) == nil)
    }

    /// Same input, same description, with or without the container; for every fixture plan.
    @Test(arguments: try fixtureCases())
    func stableForFixturePlans(_ c: FixtureCase) throws {
        let plan = try Fixtures.plan(named: c.name)
        for step in plan.placed {
            let a = describeStep(plan, items: c.items, order: step.order, container: c.container)
            #expect(a != nil)
            #expect(a == describeStep(plan, items: c.items, order: step.order, container: c.container))
            #expect(describeStep(plan, items: c.items, order: step.order) != nil)
        }
    }
}
