import Foundation

@Observable
@MainActor
final class TripStore {
    var trip: Trip?
    var bag: Container?
    var useChecked: Bool = true

    var sampleTrips: [Trip] { AppFixtures.trips() }

    func select(_ trip: Trip) {
        self.trip = trip
        self.bag = useChecked ? trip.checked : trip.carryOn
    }

    func setBag(_ container: Container) {
        bag = container
        guard var trip else { return }
        if useChecked {
            trip.checked = container
        } else {
            trip.carryOn = container
        }
        self.trip = trip
    }
}
