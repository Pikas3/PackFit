import Foundation

@Observable
@MainActor
final class TripStore {
    var trip: Trip?
    var bag: Container?
    var useChecked: Bool = true

    /// Set only after a flight is looked up / confirmed — never before.
    var weather: WeatherSummary?
    var suggestions: [Suggestion] = []
    var warnings: [TripWarning] = []
    var beforeYouGo: BeforeYouGoPanel?
    var destinationCountry: String?
    var routeNotices: [RouteNotice] = []
    var flightLabel: String?
    var isLookingUp = false
    var isLoadingSuggest = false
    var lookupError: String?
    var suggestError: String?

    func clearSelection() {
        trip = nil
        bag = nil
        weather = nil
        suggestions = []
        warnings = []
        beforeYouGo = nil
        destinationCountry = nil
        routeNotices = []
        flightLabel = nil
        lookupError = nil
        suggestError = nil
    }

    func applyLookup(_ lookup: FlightLookupResponse, nights: Int, activities: [String], useChecked: Bool) {
        self.useChecked = useChecked
        let bags = AppFixtures.containers()
        guard bags.count >= 2 else { return }
        let trip = Trip(
            id: "\(lookup.from.lowercased())-\(lookup.to.lowercased())",
            from: lookup.from,
            to: lookup.to,
            airline: lookup.airline,
            nights: nights,
            activities: activities,
            carryOn: bags[0],
            checked: bags[1],
            departDate: lookup.departDate
        )
        self.trip = trip
        self.bag = useChecked ? trip.checked : trip.carryOn
        self.flightLabel = lookup.flightLabel
        self.destinationCountry = lookup.toCountry ?? AirportCatalog.country(for: lookup.to)
        self.routeNotices = lookup.routeNotices
        // Weather / suggestions load only after the flight is confirmed.
        weather = nil
        suggestions = []
        warnings = []
        beforeYouGo = nil
        suggestError = nil
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

    func lookupFlight(airline: String, flightNumber: String, departDate: String?, client: any APIClient) async -> FlightLookupResponse? {
        isLookingUp = true
        lookupError = nil
        defer { isLookingUp = false }
        do {
            return try await client.lookupFlight(airline: airline, flightNumber: flightNumber, departDate: departDate)
        } catch {
            // Offline demo fallback so the flow never dies.
            lookupError = Copy.Errors.network
            return AppFixtures.flightLookupFallback(airline: airline, flightNumber: flightNumber, departDate: departDate)
        }
    }

    /// Destination weather + packing suggestions + before-you-go. Call only after a flight is selected.
    func loadDestinationContext(client: any APIClient) async {
        guard let trip else { return }
        isLoadingSuggest = true
        suggestError = nil
        defer { isLoadingSuggest = false }
        do {
            let response = try await client.suggestTrip(trip)
            weather = response.weather
            suggestions = response.suggestions
            warnings = response.warnings
            beforeYouGo = response.beforeYouGo
            destinationCountry = response.destinationCountry ?? AirportCatalog.country(for: trip.to)
        } catch {
            suggestError = Copy.Errors.network
            let fallback = AppFixtures.tripSuggestFallback(for: trip)
            weather = fallback.weather
            suggestions = fallback.suggestions
            warnings = fallback.warnings
            beforeYouGo = fallback.beforeYouGo
            destinationCountry = fallback.destinationCountry ?? AirportCatalog.country(for: trip.to)
        }
    }

    func openSuggestions(excluding items: [Item]) -> [Suggestion] {
        let names = Set(items.map { $0.name.lowercased() })
        return suggestions.filter { !names.contains($0.name.lowercased()) }
    }
}
