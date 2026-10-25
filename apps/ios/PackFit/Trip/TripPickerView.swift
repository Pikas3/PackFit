import SwiftUI

/// Trip details sheet: look up a flight, pick the bag and activities.
struct TripPickerView: View {
    @Environment(TripStore.self) private var tripStore
    let onDone: () -> Void

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

    private typealias P = Tokens.Palette
    private typealias T = Tokens.TypeScale

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Tokens.Spacing.lg) {
                    flightCard
                    if let pending = pendingLookup {
                        foundCard(pending)
                    }
                    activitiesCard
                }
                .padding(.horizontal, Tokens.Spacing.screen)
                .padding(.vertical, Tokens.Spacing.sm)
            }
            .packFitCanvas()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    NavTitle(title: Copy.Home.tripTitle, subtitle: Copy.Home.tripCaption)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button(Copy.Trip.cancel, action: onDone)
                }
            }
        }
        .onAppear {
            if let trip = tripStore.trip {
                airline = trip.airline
                nights = trip.nights
                date = trip.departDate ?? ""
                useChecked = tripStore.useChecked
                activityPick = Set(trip.activities.filter { activityOptions.contains($0) })
            }
        }
    }

    private var flightCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(systemImage: "airplane", title: Copy.Trip.flightHeader, caption: Copy.Trip.flightIntro)
            HStack(spacing: Tokens.Spacing.sm) {
                inputField(Copy.Trip.airlineField, text: $airline)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                inputField(Copy.Trip.flightNumberField, text: $flightNumber)
                    .keyboardType(.numberPad)
            }
            inputField(Copy.Trip.departField, text: $date)
                .keyboardType(.numbersAndPunctuation)
            Stepper(value: $nights, in: 1...60) {
                Text("\(Copy.Trip.nightsField): \(nights)")
                    .font(T.bodyBold)
                    .foregroundStyle(P.textPrimary)
            }
            HStack(spacing: Tokens.Spacing.sm) {
                Text(Copy.Trip.bagField).eyebrow()
                Spacer()
                ForEach([true, false], id: \.self) { checked in
                    Button { useChecked = checked } label: {
                        Chip(label: checked ? Copy.Trip.checkedBag : Copy.Trip.carryOnBag,
                             state: useChecked == checked ? .selected : .normal)
                    }
                    .buttonStyle(.plain)
                }
            }
            Button {
                Task { await runLookup() }
            } label: {
                HStack(spacing: Tokens.Spacing.sm) {
                    if tripStore.isLookingUp {
                        ProgressView().tint(P.pink800)
                    } else {
                        Image(systemName: "magnifyingglass")
                    }
                    Text(tripStore.isLookingUp ? Copy.Trip.lookingUp : Copy.Trip.lookupFlight)
                }
            }
            .buttonStyle(.packFitPrimary)
            .disabled(tripStore.isLookingUp)
            if let formError {
                Text(formError).font(T.caption).foregroundStyle(P.coral500)
            }
            if let lookupError = tripStore.lookupError {
                Text(lookupError).font(T.caption).foregroundStyle(P.amber500)
            }
            Text(Copy.Trip.demoFlightsHint)
                .font(T.caption)
                .foregroundStyle(P.textSecondary)
        }
        .cardStyle()
    }

    private func foundCard(_ pending: FlightLookupResponse) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(Copy.Trip.flightFound).eyebrow(P.green700)
            Text(pending.flightLabel)
                .font(T.h1)
                .foregroundStyle(P.textPrimary)
            Text("\(pending.fromName) (\(pending.from)) → \(pending.toName) (\(pending.to))")
                .font(T.bodyBold)
                .foregroundStyle(P.textPrimary)
            if pending.international, let fromC = pending.fromCountry, let toC = pending.toCountry {
                Text(Copy.Trip.internationalRoute(fromC, toC))
                    .font(T.caption)
                    .foregroundStyle(P.textSecondary)
            }
            if let depart = pending.departDate {
                Text("\(Copy.Home.dates): \(TripDates.range(departDate: depart, nights: nights))")
                    .font(T.caption)
                    .foregroundStyle(P.textSecondary)
            }
            if let note = pending.routeNote {
                Label(note, systemImage: "calendar.badge.exclamationmark")
                    .font(T.caption)
                    .foregroundStyle(P.amber500)
            }
            Button {
                confirmFlight(pending)
            } label: {
                Label(Copy.Trip.useThisFlight, systemImage: "checkmark")
            }
            .buttonStyle(.packFitPrimary)
        }
        .cardStyle(fill: P.green100, stroke: P.green400, shadow: false)
    }

    private var activitiesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(Copy.Trip.activitiesHeader).eyebrow()
            FlowLayout {
                ForEach(activityOptions, id: \.self) { option in
                    let on = activityPick.contains(option)
                    Button {
                        if on { activityPick.remove(option) } else { activityPick.insert(option) }
                    } label: {
                        Chip(label: option.capitalized, state: on ? .selected : .normal)
                    }
                    .buttonStyle(.plain)
                }
            }
            inputField(Copy.Trip.activityOther, text: $activityExtra)
        }
        .cardStyle()
    }

    private func inputField(_ prompt: String, text: Binding<String>) -> some View {
        TextField(prompt, text: text)
            .font(T.bodyBold)
            .foregroundStyle(P.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(P.pink100, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
        // The current trip stays until this lookup is confirmed, so Cancel keeps it.
        pendingLookup = await tripStore.lookupFlight(
            airline: airlineCode,
            flightNumber: number,
            departDate: date.isEmpty ? nil : date,
            client: client
        )
        if pendingLookup == nil {
            // The store's message is already shown below the button; don't repeat it.
            if tripStore.lookupError == nil { formError = Copy.Trip.flightNotFound }
        }
    }

    private func confirmFlight(_ lookup: FlightLookupResponse) {
        var activities = Array(activityPick).sorted()
        let extra = activityExtra.trimmingCharacters(in: .whitespacesAndNewlines)
        if !extra.isEmpty { activities.append(extra) }
        tripStore.applyLookup(lookup, nights: nights, activities: activities, useChecked: useChecked)
        pendingLookup = nil
        let store = tripStore
        let client = client
        Task { await store.loadDestinationContext(client: client) }
        onDone()
    }
}
