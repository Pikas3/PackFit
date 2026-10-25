import SwiftUI

/// Trip details sheet: look up a flight, pick the bag and activities.
struct TripPickerView: View {
    @Environment(TripStore.self) private var tripStore
    let onDone: () -> Void

    @State private var airline = "UA"
    @State private var flightNumber = "88"
    @State private var nights = 14
    @State private var dates = DateRangeSelection()
    @State private var showCalendar = false
    @State private var activityPick: Set<String> = ["home"]
    @State private var activityExtra = ""
    /// Activities the user typed, shown as bubbles after the presets.
    @State private var customActivities: [String] = []
    @State private var useChecked = true
    @State private var pendingLookup: FlightLookupResponse?
    @State private var formError: String?
    @FocusState private var focus: Field?

    private enum Field { case airline, flightNumber, activity }

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
                // Tapping anywhere that isn't a control puts the keyboard away.
                .contentShape(Rectangle())
                .onTapGesture { focus = nil }
            }
            .scrollDismissesKeyboard(.interactively)
            .snuglyCanvas()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    NavTitle(title: Copy.Home.tripTitle, subtitle: Copy.Home.tripCaption)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button(Copy.Trip.cancel, action: onDone)
                }
                // The number pad has no return key, so give every field a way out.
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(Copy.Trip.keyboardDone) { focus = nil }
                }
            }
        }
        .onAppear {
            if let trip = tripStore.trip {
                airline = trip.airline
                nights = trip.nights
                if let depart = TripDates.date(trip.departDate) {
                    dates = DateRangeSelection(
                        start: depart,
                        end: Calendar.current.date(byAdding: .day, value: trip.nights, to: depart)
                    )
                }
                useChecked = tripStore.useChecked
                activityPick = Set(trip.activities.filter { activityOptions.contains($0) })
                customActivities = trip.activities.filter { !activityOptions.contains($0) }
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
                    .focused($focus, equals: .airline)
                    .submitLabel(.next)
                    .onSubmit { focus = .flightNumber }
                inputField(Copy.Trip.flightNumberField, text: $flightNumber)
                    .keyboardType(.numberPad)
                    .focused($focus, equals: .flightNumber)
            }
            DateRangeCalendar(selection: $dates, isExpanded: $showCalendar)
                .padding(Tokens.Spacing.sm)
                .background(P.pink100.opacity(showCalendar ? 0.5 : 0), in: RoundedRectangle(cornerRadius: Tokens.Radius.lg, style: .continuous))
                .onChange(of: dates) { _, new in
                    if let n = new.nights { nights = n }
                }
            // Without dates the trip length still matters for packing, so keep the stepper.
            if dates.start == nil {
                Stepper(value: $nights, in: 1...DateRangeSelection.maxNights) {
                    Text("\(Copy.Trip.nightsField): \(nights)")
                        .font(T.bodyBold)
                        .foregroundStyle(P.textPrimary)
                }
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
                focus = nil
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
            .buttonStyle(.snuglyPrimary)
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
            .buttonStyle(.snuglyPrimary)
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
                // Typed activities: tap to remove.
                ForEach(customActivities, id: \.self) { custom in
                    Button {
                        customActivities.removeAll { $0 == custom }
                    } label: {
                        Chip(label: custom, state: .selected)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(Copy.Trip.removeActivity)
                }
            }
            HStack(spacing: Tokens.Spacing.sm) {
                inputField(Copy.Trip.activityOther, text: $activityExtra)
                    .focused($focus, equals: .activity)
                    .submitLabel(.done)
                    // Keep the keyboard up so several can be added in a row.
                    .onSubmit {
                        addTypedActivity()
                        focus = .activity
                    }
                Button(action: addTypedActivity) {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(P.pink800)
                        .frame(width: 44, height: 44)
                        .background(P.pink300, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(activityExtra.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel(Copy.Trip.addActivity)
            }
            // Changing activities on a trip already set up needs no new flight lookup.
            if let trip = tripStore.trip, pendingLookup == nil, activitiesWithTyped != trip.activities {
                Button {
                    addTypedActivity()
                    let store = tripStore
                    let client = client
                    store.updateActivities(selectedActivities)
                    Task { await store.loadDestinationContext(client: client) }
                    onDone()
                } label: {
                    Label(Copy.Trip.saveActivities, systemImage: "checkmark")
                }
                .buttonStyle(.snuglyPrimary)
            }
        }
        .cardStyle()
    }

    /// Presets in a stable order, then typed ones in the order they were added.
    private var selectedActivities: [String] {
        Array(activityPick).sorted() + customActivities
    }

    /// `selectedActivities` plus whatever is still in the text field.
    private var activitiesWithTyped: [String] {
        let typed = activityExtra.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else { return selectedActivities }
        var pick = activityPick
        var custom = customActivities
        Self.add(typed, options: activityOptions, pick: &pick, custom: &custom)
        return Array(pick).sorted() + custom
    }

    /// Turns the text field into a bubble. A preset typed by hand selects that preset.
    private func addTypedActivity() {
        let typed = activityExtra.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else { return }
        Self.add(typed, options: activityOptions, pick: &activityPick, custom: &customActivities)
        activityExtra = ""
    }

    private static func add(_ typed: String, options: [String], pick: inout Set<String>, custom: inout [String]) {
        if let preset = options.first(where: { $0.caseInsensitiveCompare(typed) == .orderedSame }) {
            pick.insert(preset)
        } else if !custom.contains(where: { $0.caseInsensitiveCompare(typed) == .orderedSame }) {
            custom.append(typed)
        }
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
        if dates.isPickingReturn {
            formError = Copy.Trip.needReturnDate
            showCalendar = true
            return
        }
        // The current trip stays until this lookup is confirmed, so Cancel keeps it.
        pendingLookup = await tripStore.lookupFlight(
            airline: airlineCode,
            flightNumber: number,
            departDate: dates.start.map(TripDates.iso),
            client: client
        )
        if pendingLookup == nil {
            // The store's message is already shown below the button; don't repeat it.
            if tripStore.lookupError == nil { formError = Copy.Trip.flightNotFound }
        }
    }

    private func confirmFlight(_ lookup: FlightLookupResponse) {
        addTypedActivity()
        tripStore.applyLookup(lookup, nights: nights, activities: selectedActivities, useChecked: useChecked)
        pendingLookup = nil
        let store = tripStore
        let client = client
        Task { await store.loadDestinationContext(client: client) }
        onDone()
    }
}
