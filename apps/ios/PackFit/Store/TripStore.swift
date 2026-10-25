import Foundation

@Observable
@MainActor
final class TripStore {
    var trip: Trip?
    var bag: Container?
    var useChecked: Bool = true

    /// Set only after a flight is looked up / confirmed — never before.
    var weather: WeatherSummary?
    /// Day-by-day weather from Open-Meteo for the trip's dates. Loaded on its own, so it
    /// neither waits for the suggestions call nor needs the flight to be re-confirmed.
    var destinationWeather: DestinationWeather?
    var isLoadingWeather = false
    var weatherFailed = false
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
        destinationWeather = nil
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
        destinationWeather = nil
        suggestions = []
        warnings = []
        beforeYouGo = nil
        suggestError = nil
    }

    /// New activities for the current trip; the caller reloads the suggestions.
    func updateActivities(_ activities: [String]) {
        trip?.activities = activities
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
        } catch APIError.badRequest(let message), APIError.upstream(let message) {
            // The server answered: say what it said (flight not found, lookup service down).
            lookupError = message
            return nil
        } catch let error as APIError where !error.isNetwork {
            // Reached the server but it refused or answered oddly (wrong token, bad reply).
            lookupError = error.localizedDescription
            return nil
        } catch {
            // Server unreachable: demo flights still work offline; anything else is not guessed.
            let demo = AppFixtures.flightLookupFallback(airline: airline, flightNumber: flightNumber, departDate: departDate)
            lookupError = demo == nil ? Copy.Errors.serverUnreachable : Copy.Errors.network
            return demo
        }
    }

    /// Destination weather + packing suggestions + before-you-go. Call only after a flight is selected.
    func loadDestinationContext(client: any APIClient) async {
        // Home also asks on launch; one request at a time is enough.
        guard let trip, !isLoadingSuggest else { return }
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

    /// Fetches the destination weather for the current trip; the dashboard calls it whenever
    /// the destination or dates change.
    func loadWeather() async {
        guard let trip else {
            destinationWeather = nil
            return
        }
        isLoadingWeather = true
        weatherFailed = false
        defer { isLoadingWeather = false }
        do {
            let result = try await WeatherClient.fetch(airport: trip.to, departDate: trip.departDate, nights: trip.nights)
            guard !Task.isCancelled else { return }
            destinationWeather = result
        } catch {
            guard !Task.isCancelled else { return }
            destinationWeather = nil
            weatherFailed = true
        }
    }

    func openSuggestions(excluding items: [Item]) -> [Suggestion] {
        SuggestionMatch.open(suggestions, excluding: items)
    }
}

/// Drops suggestions the user already has. A scanned "Passport" covers "Passport wallet",
/// and three scanned T-shirts cover three of five "T-shirt stack (n)" suggestions: each
/// item covers one suggestion, or as many as its name counts ("T-shirts x5").
enum SuggestionMatch {
    static func open(_ suggestions: [Suggestion], excluding items: [Item]) -> [Suggestion] {
        var unused = items.map { (category: $0.category, words: words($0.name), left: quantity($0.name)) }
        return suggestions.filter { suggestion in
            let wanted = words(suggestion.name)
            guard let head = headNoun(suggestion.name),
                  let index = unused.firstIndex(where: { item in
                      item.left > 0 && item.words.contains(head)
                          && (item.category == suggestion.category || wanted.isSubset(of: item.words))
                  })
            else { return true }
            unused[index].left -= 1
            return false
        }
    }

    /// "T-shirts x5" and "3x socks" count as 5 and 3; anything else is one.
    static func quantity(_ name: String) -> Int {
        let lowered = name.lowercased()
        for pattern in [#"\bx\s?(\d+)\b"#, #"\b(\d+)\s?x\b"#] {
            if let match = lowered.firstMatch(of: try! Regex(pattern)),
               let range = match.output[1].range,
               let n = Int(lowered[range]), n > 0 {
                return min(n, 50)
            }
        }
        return 1
    }

    /// The thing itself, ignoring sizes, colours and containers: "Phone charger cable" is
    /// "cable", "T-shirt stack (3)" is "tshirt", "Passport wallet" is "passport".
    static func headNoun(_ name: String) -> String? {
        orderedWords(name).last
    }

    static func words(_ name: String) -> Set<String> {
        Set(orderedWords(name))
    }

    private static func orderedWords(_ name: String) -> [String] {
        let lowered = name.lowercased()
            .replacingOccurrences(of: #"\(\d+\)"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\bt[\s-]?shirts?\b|\btees?\b"#, with: " tshirt ", options: .regularExpression)
        return lowered
            .split { !$0.isLetter && !$0.isNumber }
            .map { singular(String($0)) }
            .filter { $0.count > 1 && !generic.contains($0) && !$0.allSatisfy(\.isNumber) }
    }

    private static func singular(_ word: String) -> String {
        guard word.count > 3 else { return word }
        if word.hasSuffix("ies") { return String(word.dropLast(3)) + "y" }
        if word.hasSuffix("ss") || word.hasSuffix("us") { return word }
        if word.hasSuffix("s") { return String(word.dropLast()) }
        return word
    }

    /// Words that describe or hold a thing rather than name it.
    private static let generic: Set<String> = [
        "a", "an", "and", "the", "of", "for", "with", "in", "on",
        "stack", "pack", "set", "pair", "bag", "pouch", "case", "kit", "wallet", "holder", "organizer",
        "lightweight", "light", "warm", "extra", "spare", "small", "large", "mini", "compact",
        "travel", "portable", "reusable", "basic", "everyday", "clear",
    ]
}
