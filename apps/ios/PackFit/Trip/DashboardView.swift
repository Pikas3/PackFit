import SwiftUI

/// Home tab (Figma "01 · Dashboard"): the trip, the items and bag, and the pack button.
struct DashboardView: View {
    @Environment(TripStore.self) private var tripStore
    @Environment(ItemsStore.self) private var itemsStore
    @Environment(PlanStore.self) private var planStore
    @Environment(RulesStore.self) private var rulesStore
    @Environment(AppNavigator.self) private var navigator
    @Binding var path: [Route]

    @State private var showTripSheet = false
    @AppStorage("weatherFahrenheit") private var fahrenheit = true
    private let client = APIClientFactory.make()

    private typealias P = Tokens.Palette
    private typealias T = Tokens.TypeScale

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Spacing.lg) {
                brandBar
                greeting
                nextTripCard
                photosSection
                itinerarySection
                cta
            }
            .padding(.horizontal, Tokens.Spacing.screen)
            .padding(.vertical, Tokens.Spacing.sm)
        }
        .packFitCanvas()
        .toolbar(.hidden, for: .navigationBar)
        // Refetch the weather whenever the destination or the dates change, and on launch.
        .task(id: weatherKey) { await tripStore.loadWeather() }
        .sheet(isPresented: $showTripSheet) {
            TripPickerView { showTripSheet = false }
        }
    }

    // MARK: Header

    private var brandBar: some View {
        HStack {
            HStack(spacing: Tokens.Spacing.sm) {
                Image(systemName: "suitcase")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(P.pink800)
                    .frame(width: 34, height: 34)
                    .background(P.pink300, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                (Text("Pack").foregroundStyle(P.textPrimary) + Text("Fit").foregroundStyle(P.pink700))
                    .font(T.wordmark)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Copy.App.name)
            .accessibilityAddTraits(.isHeader)

            Spacer()

            Button { path.append(.rules) } label: {
                Image(systemName: "bell")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(P.textPrimary)
                    .frame(width: 40, height: 40)
                    .background(P.surface, in: Circle())
                    .shadow(color: P.shadow, radius: 6, y: 8)
                    .overlay(alignment: .topTrailing) {
                        if !rulesStore.flags.isEmpty {
                            Text("\(rulesStore.flags.count)")
                                .font(.custom(Tokens.FontName.nunitoExtraBold, size: 10))
                                .foregroundStyle(P.surface)
                                .padding(4)
                                .background(P.coral500, in: Circle())
                                .offset(x: 2, y: -2)
                        }
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(Copy.Home.alerts), \(rulesStore.flags.count)")
        }
    }

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(Copy.Home.greeting)
                .font(T.bodyBold)
                .foregroundStyle(P.pink700)
            Text(Copy.Home.title)
                .font(T.display)
                .foregroundStyle(P.textPrimary)
        }
    }

    private var nextTripCard: some View {
        Button { showTripSheet = true } label: {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
                    Text(Copy.Home.nextTrip).eyebrow(P.pink700)
                    Text(tripHeadline)
                        .font(T.h1)
                        .foregroundStyle(P.textPrimary)
                    Text(tripStore.trip == nil ? Copy.Home.noTripBody : Copy.Home.tripBody)
                        .font(T.caption)
                        .foregroundStyle(P.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: tripStore.trip == nil ? "airplane.departure" : "suitcase.rolling")
                    .font(.system(size: 30, weight: .regular))
                    .foregroundStyle(P.pink700)
                    .frame(width: 72, height: 72)
                    .background(P.surface, in: RoundedRectangle(cornerRadius: Tokens.Radius.card, style: .continuous))
                    .shadow(color: P.shadow, radius: 12, y: 8)
            }
            .padding(Tokens.Spacing.screen)
            .background(P.pink100, in: RoundedRectangle(cornerRadius: Tokens.Radius.hero, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: Section 1: photos

    private var photosSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(number: "1", title: Copy.Home.snapTitle, caption: Copy.Home.snapCaption)
            HStack(alignment: .top, spacing: 12) {
                itemsTile
                bagTile
            }
            TipRow(text: Copy.Home.snapTip)
        }
    }

    @ViewBuilder
    private var itemsTile: some View {
        if itemsStore.items.isEmpty {
            Button { path.append(.inventoryScan) } label: {
                emptyTile(systemImage: "camera", title: Copy.Home.itemsTile, caption: Copy.Home.itemsEmpty, action: Copy.Home.addPhoto)
            }
            .buttonStyle(.plain)
        } else {
            Button { path.append(.itemList) } label: {
                filledTile(
                    systemImage: "tshirt",
                    title: Copy.Home.itemsTile,
                    caption: Copy.Home.itemsFound(itemsStore.items.count),
                    thumbnails: distinctCategories
                )
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var bagTile: some View {
        Button { path.append(.bagSetup) } label: {
            if let bag = tripStore.bag {
                filledTile(
                    systemImage: "suitcase",
                    title: Copy.Home.bagTile,
                    caption: "\(bag.name) · \(Int(bag.weightLimitKg)) kg",
                    thumbnails: []
                )
            } else {
                emptyTile(systemImage: "camera", title: Copy.Home.bagTile, caption: Copy.Home.bagEmpty, action: Copy.Home.addBag)
            }
        }
        .buttonStyle(.plain)
    }

    /// `Upload Tile · (Uploaded)`: green, with a done badge.
    private func filledTile(systemImage: String, title: String, caption: String, thumbnails: [Category]) -> some View {
        VStack(alignment: .leading) {
            HStack(alignment: .top) {
                IconBubble(systemImage: systemImage, size: 44, iconSize: 22, radius: 16, fill: P.surface, tint: P.green700)
                Spacer()
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(P.green800)
                    .frame(width: 24, height: 24)
                    .background(P.green400, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            Spacer(minLength: Tokens.Spacing.sm)
            if !thumbnails.isEmpty {
                HStack(spacing: 6) {
                    ForEach(Array(thumbnails.enumerated()), id: \.offset) { _, category in
                        Image(systemName: category.systemImage)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(P.pink700)
                            .frame(width: 34, height: 34)
                            .background(category.swatch, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(P.surface, lineWidth: 2)
                            }
                    }
                }
                .accessibilityHidden(true)
                Spacer(minLength: Tokens.Spacing.sm)
            }
            Text(title).font(T.h3).foregroundStyle(P.textPrimary)
            Text(caption)
                .font(T.caption)
                .foregroundStyle(P.green700)
                .multilineTextAlignment(.leading)
        }
        .padding(Tokens.Spacing.md)
        .frame(maxWidth: .infinity, minHeight: 188, alignment: .topLeading)
        .background(P.green100, in: RoundedRectangle(cornerRadius: Tokens.Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Tokens.Radius.card, style: .continuous).strokeBorder(P.green400, lineWidth: 1.5)
        }
        .accessibilityElement(children: .combine)
    }

    /// `Upload Tile · (Empty)`: dashed pink outline with a camera.
    private func emptyTile(systemImage: String, title: String, caption: String, action: String) -> some View {
        VStack(spacing: Tokens.Spacing.sm) {
            IconBubble(systemImage: systemImage, size: 52, iconSize: 24, radius: 18)
            Text(title).font(T.h3).foregroundStyle(P.textPrimary)
            Text(caption)
                .font(T.caption)
                .foregroundStyle(P.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            PillLabel(title: action, systemImage: "plus")
        }
        .padding(Tokens.Spacing.md)
        .frame(maxWidth: .infinity, minHeight: 188)
        .background(P.surface, in: RoundedRectangle(cornerRadius: Tokens.Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Tokens.Radius.card, style: .continuous)
                .strokeBorder(P.pink300, style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Section 2: itinerary

    private var itinerarySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(number: "2", title: Copy.Home.tripTitle, caption: Copy.Home.tripCaption)
            VStack(alignment: .leading, spacing: 6) {
                Button { showTripSheet = true } label: {
                    VStack(spacing: 6) {
                        field("airplane", Copy.Home.from, trip.map { airportLabel($0.from) })
                        divider
                        field("mappin.and.ellipse", Copy.Home.to, trip.map { airportLabel($0.to) })
                        divider
                        field("calendar", Copy.Home.dates, trip.map { TripDates.range(departDate: $0.departDate, nights: $0.nights) })
                        divider
                        field("suitcase", Copy.Home.airlineBag, trip.map { _ in airlineBagLabel })
                    }
                }
                .buttonStyle(.plain)
                divider
                weatherSection
            }
            .cardStyle()

            if trip != nil {
                HStack(spacing: Tokens.Spacing.sm) {
                    Button { path.append(.suggestions) } label: {
                        PillLabel(title: Copy.Home.packingIdeas, systemImage: "sparkles")
                    }
                    Button { path.append(.beforeYouGo) } label: {
                        PillLabel(title: Copy.Trip.beforeYouGoCTA, systemImage: "globe")
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func field(_ icon: String, _ label: String, _ value: String?) -> some View {
        ItineraryField(systemImage: icon, label: label, value: value ?? Copy.Home.addFlight, isPlaceholder: value == nil)
    }

    private var divider: some View {
        Rectangle().fill(P.pink100).frame(height: 1)
    }

    // MARK: Weather

    private var weatherSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(Copy.Home.weatherIn(trip.flatMap { AirportCatalog.name(for: $0.to) })).eyebrow()
                Spacer()
                if tripStore.destinationWeather != nil {
                    unitSwitcher
                }
            }
            weatherBody
        }
        .padding(.top, Tokens.Spacing.sm)
    }

    @ViewBuilder
    private var weatherBody: some View {
        if let trip {
            if let weather = tripStore.destinationWeather {
                weatherSummary(weather, nights: trip.nights)
            } else if tripStore.isLoadingWeather {
                HStack(spacing: Tokens.Spacing.sm) {
                    ProgressView().tint(P.pink700)
                    Text(Copy.Home.loadingWeather)
                }
                .font(T.caption)
                .foregroundStyle(P.textSecondary)
            } else if trip.departDate == nil {
                weatherNote(Copy.Home.weatherNeedsDates)
            } else if tripStore.weatherFailed {
                VStack(alignment: .leading, spacing: 6) {
                    // The server's summary, when the suggestions call brought one, beats nothing.
                    weatherNote(tripStore.weather?.summary ?? Copy.Home.weatherFailed)
                    Button(Copy.Home.retry) { Task { await tripStore.loadWeather() } }
                        .font(T.caption.weight(.bold))
                        .foregroundStyle(P.pink700)
                }
            }
        } else {
            weatherNote(Copy.Home.noForecast)
        }
    }

    private func weatherSummary(_ weather: DestinationWeather, nights: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                IconBubble(systemImage: WeatherCode.symbol(weather.typicalCode), size: 48, iconSize: 22, radius: Tokens.Radius.md, fill: P.pink100)
                VStack(alignment: .leading, spacing: 2) {
                    Text(Copy.Home.tempRange(low: degrees(weather.lowC), high: degrees(weather.highC), fahrenheit: fahrenheit))
                        .font(T.h2)
                        .foregroundStyle(P.textPrimary)
                    Text(Copy.Home.wetDays(weather.wetDays, of: weather.days.count))
                        .font(T.caption)
                        .foregroundStyle(P.textSecondary)
                }
                Spacer(minLength: 0)
                Chip(
                    label: weather.source == .forecast ? Copy.Home.forecastTag : Copy.Home.lastYearTag,
                    state: weather.source == .forecast ? .selected : .normal
                )
            }
            .accessibilityElement(children: .combine)
            if weather.source == .forecast {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Tokens.Spacing.sm) {
                        ForEach(weather.days) { day in
                            dayColumn(day)
                        }
                    }
                }
            }
            if weather.source == .lastYear {
                weatherNote(Copy.Home.lastYearNote)
            } else if weather.clamped, let lastDay = weather.days.last {
                weatherNote(Copy.Home.clampedNote(lastDay.date))
            }
        }
    }

    private func dayColumn(_ day: DestinationWeather.Day) -> some View {
        VStack(spacing: 4) {
            VStack(spacing: 0) {
                Text(day.date.formatted(DestinationWeather.dayStyle.weekday(.abbreviated)))
                    .font(T.caption)
                    .foregroundStyle(P.textSecondary)
                Text(day.date.formatted(DestinationWeather.dayStyle.month(.twoDigits).day(.twoDigits)))
                    .font(T.caption)
                    .foregroundStyle(P.textSecondary)
                    .monospacedDigit()
            }
            Image(systemName: WeatherCode.symbol(day.code))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(P.pink700)
                .frame(height: 22)
            Text("\(degrees(day.highC))°")
                .font(T.bodyBold)
                .foregroundStyle(P.textPrimary)
            Text("\(degrees(day.lowC))°")
                .font(T.caption)
                .foregroundStyle(P.textSecondary)
        }
        .frame(width: 52)
        .padding(.vertical, 8)
        .background(P.pink100.opacity(0.6), in: RoundedRectangle(cornerRadius: Tokens.Radius.sm, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    /// °F or °C, remembered per device; °F first.
    private var unitSwitcher: some View {
        HStack(spacing: Tokens.Spacing.xs) {
            ForEach([true, false], id: \.self) { isF in
                Button { fahrenheit = isF } label: {
                    Chip(label: isF ? "°F" : "°C", state: fahrenheit == isF ? .selected : .plain)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isF ? Copy.Home.fahrenheit : Copy.Home.celsius)
                .accessibilityAddTraits(fahrenheit == isF ? .isSelected : [])
            }
        }
        .padding(Tokens.Spacing.xs)
        .background(P.pink100, in: Capsule())
    }

    /// A Celsius reading in the chosen unit, rounded.
    private func degrees(_ celsius: Double) -> Int {
        Int((fahrenheit ? celsius * 9 / 5 + 32 : celsius).rounded())
    }

    private func weatherNote(_ text: String) -> some View {
        Text(text)
            .font(T.caption)
            .foregroundStyle(P.pink700)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: CTA

    private var cta: some View {
        VStack(spacing: 10) {
            Button {
                Task { await optimize() }
            } label: {
                HStack(spacing: Tokens.Spacing.sm) {
                    if planStore.isPacking {
                        ProgressView().tint(P.pink800)
                    } else {
                        Image(systemName: "sparkles")
                    }
                    Text(Copy.Home.optimize)
                }
            }
            .buttonStyle(.packFitPrimary)
            .disabled(!canPack || planStore.isPacking)

            Text(canPack ? Copy.Home.optimizeCaption(itemsStore.items.count) : Copy.Home.needTrip)
                .font(T.caption)
                .foregroundStyle(P.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Tokens.Spacing.xs)
    }

    // MARK: Data

    private var trip: Trip? { tripStore.trip }

    /// Up to three different categories, in list order, for the item tile thumbnails.
    private var distinctCategories: [Category] {
        var seen: [Category] = []
        for item in itemsStore.items where !seen.contains(item.category) {
            seen.append(item.category)
            if seen.count == 3 { break }
        }
        return seen
    }

    private var canPack: Bool {
        tripStore.trip != nil && tripStore.bag != nil && !itemsStore.items.isEmpty
    }

    private var tripHeadline: String {
        guard let trip else { return Copy.Home.noTrip }
        let place = AirportCatalog.name(for: trip.to) ?? trip.to
        if let days = TripDates.daysUntil(trip.departDate) {
            return Copy.Home.inDays(place, days)
        }
        return Copy.Home.nights(place, trip.nights)
    }

    private func airportLabel(_ code: String) -> String {
        guard let name = AirportCatalog.name(for: code) else { return code }
        return "\(name) (\(code))"
    }

    private var airlineBagLabel: String {
        let flight = tripStore.flightLabel ?? trip?.airline ?? ""
        guard let bag = tripStore.bag else { return flight }
        return "\(flight) · \(tripStore.useChecked ? Copy.Trip.checkedBag : Copy.Trip.carryOnBag) (\(Int(bag.weightLimitKg)) kg)"
    }

    private var weatherKey: String {
        guard let trip else { return "" }
        return "\(trip.to)|\(trip.departDate ?? "")|\(trip.nights)"
    }

    private func optimize() async {
        guard let trip = tripStore.trip, let bag = tripStore.bag else { return }
        await PackRun.run(
            trip: trip, bag: bag, useChecked: tripStore.useChecked, items: itemsStore.items,
            planStore: planStore, rulesStore: rulesStore, client: client
        )
        navigator.tab = .results
    }
}

/// Checks the rules, drops banned items and packs the rest. Shared by Home and the item list.
@MainActor
enum PackRun {
    static func run(
        trip: Trip, bag: Container, useChecked: Bool, items: [Item],
        planStore: PlanStore, rulesStore: RulesStore, client: any APIClient
    ) async {
        // Mark packing during the rules check too, so the spinner and disabled buttons cover it.
        planStore.isPacking = true
        await rulesStore.check(items: items, trip: trip, bag: useChecked ? "checked" : "carryOn", client: client)
        let banned = Set(rulesStore.flags.filter { $0.severity == .banned }.map(\.itemId))
        await planStore.computePlan(items: items.filter { !banned.contains($0.id) }, into: bag)
    }
}

/// Date helpers for the trip card and itinerary.
enum TripDates {
    private static let isoDay: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func date(_ iso: String?) -> Date? {
        iso.flatMap { isoDay.date(from: String($0.prefix(10))) }
    }

    static func iso(_ date: Date) -> String {
        isoDay.string(from: date)
    }

    static func daysUntil(_ iso: String?) -> Int? {
        guard let depart = date(iso) else { return nil }
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: .now), to: cal.startOfDay(for: depart)).day
        return days.map { max($0, 0) }
    }

    /// "Dec 12 – Dec 20 · 8 nights", or just the nights without a date.
    static func range(departDate: String?, nights: Int) -> String {
        let nightsText = nights == 1 ? "1 night" : "\(nights) nights"
        guard let start = date(departDate),
              let end = Calendar.current.date(byAdding: .day, value: nights, to: start) else { return nightsText }
        let style = Date.FormatStyle().month(.abbreviated).day()
        return "\(start.formatted(style)) – \(end.formatted(style)) · \(nightsText)"
    }
}
