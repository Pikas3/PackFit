import SwiftUI

struct TripPickerView: View {
    @Environment(TripStore.self) private var tripStore
    @Environment(DeviceCapabilities.self) private var caps
    @Environment(\.openURL) private var openURL
    @Binding var path: [Route]

    @State private var airline = "UA"
    @State private var flightNumber = "88"
    @State private var nights = 14
    @State private var date = ""
    @State private var activityPick: Set<String> = ["home"]
    @State private var activityExtra = ""
    @State private var useChecked = true
    @State private var pendingLookup: FlightLookupResponse?
    @State private var formError: String?

    private let client = APIClientFactory.make()
    private let activityOptions = ["home", "school", "work", "beach", "hike", "ski", "cold", "wedding", "conference"]

    var body: some View {
        List {
            Section {
                Text(Copy.Trip.flightIntro)
                    .font(Tokens.TypeScale.callout)
                    .foregroundStyle(.secondary)
                TextField(Copy.Trip.airlineField, text: $airline)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                TextField(Copy.Trip.flightNumberField, text: $flightNumber)
                    .keyboardType(.numberPad)
                    .autocorrectionDisabled()
                TextField(Copy.Trip.departField, text: $date)
                    .keyboardType(.numbersAndPunctuation)
                Stepper("\(Copy.Trip.nightsField): \(nights)", value: $nights, in: 1...60)
                Picker(Copy.Trip.bagField, selection: $useChecked) {
                    Text(Copy.Trip.checkedBag).tag(true)
                    Text(Copy.Trip.carryOnBag).tag(false)
                }
                Button(Copy.Trip.lookupFlight) {
                    Task { await runLookup() }
                }
                .buttonStyle(.borderedProminent)
                .tint(Tokens.Color.brand)
                .disabled(tripStore.isLookingUp)
                if tripStore.isLookingUp {
                    ProgressView(Copy.Trip.lookingUp)
                }
                if let formError {
                    Text(formError).foregroundStyle(Tokens.Color.banned)
                }
                if let lookupError = tripStore.lookupError {
                    Text(lookupError)
                        .font(Tokens.TypeScale.caption)
                        .foregroundStyle(Tokens.Color.restricted)
                }
            } header: {
                Text(Copy.Trip.flightHeader)
            } footer: {
                Text(Copy.Trip.demoFlightsHint)
                    .font(Tokens.TypeScale.caption)
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

            if let pending = pendingLookup {
                Section(Copy.Trip.flightFound) {
                    Text(pending.flightLabel)
                        .font(Tokens.TypeScale.title)
                    Text("\(pending.fromName) (\(pending.from)) → \(pending.toName) (\(pending.to))")
                        .font(Tokens.TypeScale.body)
                    if pending.international, let fromC = pending.fromCountry, let toC = pending.toCountry {
                        Text(Copy.Trip.internationalRoute(fromC, toC))
                            .font(Tokens.TypeScale.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let depart = pending.departDate {
                        Text("\(Copy.Trip.departField): \(depart)")
                            .font(Tokens.TypeScale.caption)
                    }
                    Button(Copy.Trip.useThisFlight) {
                        Task { await confirmFlight(pending) }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Tokens.Color.brand)
                    .disabled(tripStore.isLoadingSuggest)
                }
            }

            // Weather + destination context only after the flight is confirmed.
            if tripStore.trip != nil {
                if tripStore.isLoadingSuggest {
                    Section { ProgressView(Copy.Trip.loadingDestination) }
                }

                if let weather = tripStore.weather {
                    Section(Copy.Trip.weatherHeader) {
                        Text(weather.summary)
                            .font(Tokens.TypeScale.callout)
                        Text(Copy.Trip.weatherAtDestination(tripStore.trip?.to ?? ""))
                            .font(Tokens.TypeScale.caption)
                            .foregroundStyle(.secondary)
                        ForEach(tripStore.warnings, id: \.plainLanguage) { warning in
                            Text(warning.plainLanguage)
                                .font(Tokens.TypeScale.caption)
                                .foregroundStyle(Tokens.Color.restricted)
                        }
                    }
                }

                if !tripStore.routeNotices.isEmpty {
                    Section(Copy.Trip.routeRulesHeader) {
                        Text(Copy.Rules.guidance)
                            .font(Tokens.TypeScale.caption)
                            .foregroundStyle(.secondary)
                        ForEach(tripStore.routeNotices) { notice in
                            VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
                                Text(notice.scope.uppercased())
                                    .font(Tokens.TypeScale.caption.weight(.semibold))
                                Text(notice.text)
                                Button(Copy.Trip.sourceLink) {
                                    if let url = URL(string: notice.sourceUrl) { openURL(url) }
                                }
                                .font(Tokens.TypeScale.caption)
                            }
                        }
                    }
                }

                Section {
                    Button(Copy.Trip.suggestionsCTA) { path.append(.suggestions) }
                    Button(Copy.Trip.beforeYouGoCTA) { path.append(.beforeYouGo) }
                    Button(Copy.Trip.continueButton) { path.append(nextRoute) }
                        .buttonStyle(.borderedProminent)
                        .tint(Tokens.Color.brand)
                }
            }
        }
        .navigationTitle(Copy.Trip.title)
        .onAppear {
            // Don't show leftover weather from a previous session without a confirmed trip.
            if tripStore.trip == nil {
                tripStore.clearSelection()
                pendingLookup = nil
            }
        }
    }

    private var nextRoute: Route {
        caps.supportsGuidedScan ? .guidedScan : .bagSetup
    }

    private func runLookup() async {
        formError = nil
        pendingLookup = nil
        let airlineCode = airline.trimmingCharacters(in: .whitespacesAndNewlines)
        let number = flightNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !airlineCode.isEmpty, !number.isEmpty else {
            formError = Copy.Trip.needFlightFields
            return
        }
        if !date.isEmpty, date.count != 10 {
            formError = Copy.Trip.invalidDate
            return
        }
        // Clear previous trip/weather until this lookup is confirmed.
        tripStore.clearSelection()
        pendingLookup = await tripStore.lookupFlight(
            airline: airlineCode,
            flightNumber: number,
            departDate: date.isEmpty ? nil : date,
            client: client
        )
        if pendingLookup == nil {
            formError = tripStore.lookupError ?? Copy.Trip.flightNotFound
        }
    }

    private func confirmFlight(_ lookup: FlightLookupResponse) async {
        var activities = Array(activityPick).sorted()
        let extra = activityExtra.trimmingCharacters(in: .whitespacesAndNewlines)
        if !extra.isEmpty { activities.append(extra) }
        tripStore.applyLookup(lookup, nights: nights, activities: activities, useChecked: useChecked)
        pendingLookup = nil
        await tripStore.loadDestinationContext(client: client)
    }
}
