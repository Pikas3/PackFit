import Foundation

@Observable
@MainActor
final class TripStore {
    var trip: Trip?
    var bag: Container?
    var useChecked: Bool = true

    var weather: WeatherSummary?
    var suggestions: [Suggestion] = []
    var warnings: [TripWarning] = []
    var beforeYouGo: BeforeYouGoPanel?
    var destinationCountry: String?
    var isLoadingSuggest = false
    var suggestError: String?

    var sampleTrips: [Trip] { AppFixtures.trips() }

    func select(_ trip: Trip) {
        self.trip = trip
        self.bag = useChecked ? trip.checked : trip.carryOn
        destinationCountry = AirportCatalog.country(for: trip.to)
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

    /// Loads weather, suggestions, and before-you-go tips. Offline/mock fallback on failure.
    func loadSuggestions(client: any APIClient) async {
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

    /// Suggestions that are not already in the scanned list (by name, case-insensitive).
    func openSuggestions(excluding items: [Item]) -> [Suggestion] {
        let names = Set(items.map { $0.name.lowercased() })
        return suggestions.filter { !names.contains($0.name.lowercased()) }
    }
}
