import SwiftUI

struct TripPickerView: View {
    @Environment(TripStore.self) private var tripStore
    @Environment(DeviceCapabilities.self) private var caps
    @Binding var path: [Route]

    @State private var showNew = false
    @State private var from = "SFO"
    @State private var to = "DEL"
    @State private var airline = "UA"
    @State private var nights = 14
    @State private var date = ""
    @State private var activityPick: Set<String> = ["home"]
    @State private var activityExtra = ""
    @State private var useChecked = true
    @State private var formError: String?
    @State private var fromQuery = ""
    @State private var toQuery = ""

    private let client = APIClientFactory.make()
    private let activityOptions = ["home", "school", "work", "beach", "hike", "ski", "cold", "wedding", "conference"]

    var body: some View {
        List {
            if let weather = tripStore.weather, tripStore.trip != nil {
                Section(Copy.Trip.weatherHeader) {
                    Text(weather.summary)
                        .font(Tokens.TypeScale.callout)
                    ForEach(tripStore.warnings, id: \.plainLanguage) { warning in
                        Text(warning.plainLanguage)
                            .font(Tokens.TypeScale.caption)
                            .foregroundStyle(Tokens.Color.restricted)
                    }
                    if tripStore.isLoadingSuggest {
                        ProgressView()
                    }
                    Button(Copy.Trip.suggestionsCTA) { path.append(.suggestions) }
                    Button(Copy.Trip.beforeYouGoCTA) { path.append(.beforeYouGo) }
                }
            }

            Section(Copy.Trip.sampleHeader) {
                ForEach(Array(tripStore.sampleTrips.enumerated()), id: \.offset) { _, trip in
                    Button {
                        Task { await selectAndContinue(trip) }
                    } label: {
                        VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
                            Text("\(trip.from) → \(trip.to)")
                                .font(Tokens.TypeScale.title)
                                .foregroundStyle(.primary)
                            Text("\(trip.airline) · \(trip.nights) nights · \(Int(trip.checked.weightLimitKg)) kg checked")
                                .font(Tokens.TypeScale.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section {
                Button(Copy.Trip.newTrip) { showNew = true }
            }
        }
        .navigationTitle(Copy.Trip.title)
        .sheet(isPresented: $showNew) { newTripForm }
    }

    private var nextRoute: Route {
        caps.supportsGuidedScan ? .guidedScan : .bagSetup
    }

    private var newTripForm: some View {
        NavigationStack {
            Form {
                Section(Copy.Trip.fromSection) {
                    TextField(Copy.Trip.airportPlaceholder, text: $fromQuery)
                        .textInputAutocapitalization(.characters)
                        .onChange(of: fromQuery) { _, q in
                            if let hit = AirportCatalog.match(q).first, hit.code == q.uppercased() {
                                from = hit.code
                            }
                        }
                    ForEach(AirportCatalog.match(fromQuery)) { airport in
                        Button("\(airport.code) — \(airport.name)") {
                            from = airport.code
                            fromQuery = airport.code
                        }
                    }
                }
                Section(Copy.Trip.toSection) {
                    TextField(Copy.Trip.airportPlaceholder, text: $toQuery)
                        .textInputAutocapitalization(.characters)
                    ForEach(AirportCatalog.match(toQuery)) { airport in
                        Button("\(airport.code) — \(airport.name)") {
                            to = airport.code
                            toQuery = airport.code
                        }
                    }
                    if let country = AirportCatalog.country(for: to) {
                        Text(Copy.Trip.countryResolved(country))
                            .font(Tokens.TypeScale.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Section {
                    TextField(Copy.Trip.airlineField, text: $airline)
                        .textInputAutocapitalization(.characters)
                    Stepper("\(Copy.Trip.nightsField): \(nights)", value: $nights, in: 1...60)
                    TextField(Copy.Trip.departField, text: $date)
                        .keyboardType(.numbersAndPunctuation)
                    Picker(Copy.Trip.bagField, selection: $useChecked) {
                        Text(Copy.Trip.checkedBag).tag(true)
                        Text(Copy.Trip.carryOnBag).tag(false)
                    }
                }
                Section(Copy.Trip.activitiesHeader) {
                    ForEach(activityOptions, id: \.self) { option in
                        Toggle(option.capitalized, isOn: Binding(
                            get: { activityPick.contains(option) },
                            set: { on in
                                if on { activityPick.insert(option) } else { activityPick.remove(option) }
                            }
                        ))
                    }
                    TextField(Copy.Trip.activityOther, text: $activityExtra)
                }
                if let formError {
                    Section { Text(formError).foregroundStyle(Tokens.Color.banned) }
                }
            }
            .navigationTitle(Copy.Trip.newTrip)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Copy.Trip.cancel) { showNew = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(Copy.Trip.continueButton) {
                        Task { await submitNewTrip() }
                    }
                }
            }
        }
    }

    private func submitNewTrip() async {
        formError = nil
        let fromCode = (fromQuery.isEmpty ? from : fromQuery).uppercased()
        let toCode = (toQuery.isEmpty ? to : toQuery).uppercased()
        guard fromCode.count == 3, toCode.count == 3 else {
            formError = Copy.Trip.invalidAirport
            return
        }
        if !AirportCatalog.isKnownAirport(toCode) {
            formError = Copy.Trip.unknownAirport
            return
        }
        if !date.isEmpty, date.count != 10 {
            formError = Copy.Trip.invalidDate
            return
        }
        let airlineCode = airline.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let bags = AppFixtures.containers()
        guard bags.count >= 2 else {
            formError = Copy.Errors.generic
            return
        }
        var activities = Array(activityPick).sorted()
        let extra = activityExtra.trimmingCharacters(in: .whitespacesAndNewlines)
        if !extra.isEmpty { activities.append(extra) }
        let trip = Trip(
            id: "\(fromCode.lowercased())-\(toCode.lowercased())",
            from: fromCode,
            to: toCode,
            airline: airlineCode.isEmpty ? "UA" : airlineCode,
            nights: nights,
            activities: activities,
            carryOn: bags[0],
            checked: bags[1],
            departDate: date.isEmpty ? nil : date
        )
        tripStore.useChecked = useChecked
        showNew = false
        await selectAndContinue(trip)
    }

    private func selectAndContinue(_ trip: Trip) async {
        tripStore.select(trip)
        await tripStore.loadSuggestions(client: client)
        path.append(nextRoute)
    }
}
