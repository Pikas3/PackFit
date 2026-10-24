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

    var body: some View {
        List {
            Section(Copy.Trip.sampleHeader) {
                ForEach(Array(tripStore.sampleTrips.enumerated()), id: \.offset) { _, trip in
                    Button {
                        tripStore.select(trip)
                        path.append(nextRoute)
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

    /// AR-capable phones go straight to the guided scan (LiDAR sweep or AR taps).
    private var nextRoute: Route {
        caps.supportsAR ? .guidedScan : .bagSetup
    }

    private var newTripForm: some View {
        NavigationStack {
            Form {
                TextField("From (IATA)", text: $from)
                TextField("To (IATA)", text: $to)
                TextField("Airline", text: $airline)
                Stepper("Nights: \(nights)", value: $nights, in: 1...60)
                TextField("Depart (YYYY-MM-DD)", text: $date)
            }
            .navigationTitle(Copy.Trip.newTrip)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showNew = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(Copy.Trip.continueButton) {
                        let bags = AppFixtures.containers()
                        guard bags.count >= 2 else { return }
                        let trip = Trip(
                            id: "\(from.lowercased())-\(to.lowercased())",
                            from: from.uppercased(),
                            to: to.uppercased(),
                            airline: airline.uppercased(),
                            nights: nights,
                            activities: [],
                            carryOn: bags[0],
                            checked: bags[1],
                            departDate: date.isEmpty ? nil : date
                        )
                        tripStore.select(trip)
                        showNew = false
                        path.append(nextRoute)
                    }
                }
            }
        }
    }
}
