import Foundation

/// Weather at the destination for the trip's dates, straight from Open-Meteo (no key, so the
/// app may call it directly). Inside the 16-day forecast range it is the forecast; further out
/// it is the same dates last year, labelled as such. Mirrors `weatherWindow` in
/// services/api/src/services/trip.ts, which feeds the packing suggestions.
struct DestinationWeather: Equatable, Sendable {
    enum Source: Equatable, Sendable { case forecast, lastYear }

    struct Day: Equatable, Sendable, Identifiable {
        var date: Date
        var highC: Double
        var lowC: Double
        var precipMM: Double
        var precipChance: Double?
        var code: Int
        var id: Date { date }

        var isWet: Bool { precipMM >= 1 || (precipChance ?? 0) >= 0.5 }
    }

    var source: Source
    var days: [Day]
    /// The forecast stops before the trip ends.
    var clamped: Bool

    /// Day dates are midnight UTC (the destination's calendar day); format them in UTC so a
    /// viewer west of Greenwich doesn't see the day before.
    static let dayStyle = Date.FormatStyle(timeZone: TimeZone(identifier: "UTC")!)

    var highC: Double { days.map(\.highC).max() ?? 0 }
    var lowC: Double { days.map(\.lowC).min() ?? 0 }
    var wetDays: Int { days.filter(\.isWet).count }

    /// The most common condition, so one rainy day doesn't make the whole trip look wet.
    var typicalCode: Int {
        let counts = Dictionary(grouping: days.map { WeatherCode.group($0.code) }, by: { $0 }).mapValues(\.count)
        let group = counts.max { $0.value < $1.value || ($0.value == $1.value && $0.key > $1.key) }?.key ?? 0
        return group
    }
}

enum WeatherWindow {
    /// Open-Meteo's forecast reaches this many days ahead, today included.
    static let forecastDays = 16

    struct Range: Equatable {
        var source: DestinationWeather.Source
        var start: String
        var end: String
        var clamped: Bool
    }

    /// Dates to ask for, as yyyy-MM-dd in UTC like the server.
    static func range(departDate: String, nights: Int, today: Date = .now) -> Range? {
        guard let start = day(departDate) else { return nil }
        let end = add(start, max(0, nights))
        let first = utc.startOfDay(for: today)
        let last = add(first, forecastDays - 1)
        if start >= first && start <= last {
            return Range(source: .forecast, start: iso(start), end: iso(min(end, last)), clamped: end > last)
        }
        // Last year's archive ends a few days before today; step back another year if needed.
        let archiveEnd = add(first, -6)
        var years = 1
        while add(end, years: -years) > archiveEnd { years += 1 }
        return Range(
            source: .lastYear,
            start: iso(add(start, years: -years)),
            end: iso(add(end, years: -years)),
            clamped: false
        )
    }

    private static let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = utc
        f.timeZone = utc.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func day(_ iso: String) -> Date? { formatter.date(from: String(iso.prefix(10))) }
    static func iso(_ date: Date) -> String { formatter.string(from: date) }
    private static func add(_ date: Date, _ days: Int) -> Date { utc.date(byAdding: .day, value: days, to: date)! }
    private static func add(_ date: Date, years: Int) -> Date { utc.date(byAdding: .year, value: years, to: date)! }
}

enum WeatherClient {
    enum Failure: Error { case unknownAirport, noDate, noData }

    static func fetch(airport: String, departDate: String?, nights: Int) async throws -> DestinationWeather {
        guard let coords = AirportCatalog.coordinates(for: airport) else { throw Failure.unknownAirport }
        guard let departDate, let range = WeatherWindow.range(departDate: departDate, nights: nights) else {
            throw Failure.noDate
        }
        let forecast = range.source == .forecast
        var components = URLComponents(string: forecast
            ? "https://api.open-meteo.com/v1/forecast"
            : "https://archive-api.open-meteo.com/v1/archive")!
        var daily = ["temperature_2m_max", "temperature_2m_min", "precipitation_sum", "weather_code"]
        if forecast { daily.append("precipitation_probability_max") }
        components.queryItems = [
            .init(name: "latitude", value: String(coords.lat)),
            .init(name: "longitude", value: String(coords.lon)),
            .init(name: "daily", value: daily.joined(separator: ",")),
            .init(name: "timezone", value: "auto"),
            .init(name: "start_date", value: range.start),
            .init(name: "end_date", value: range.end),
        ]
        let url = components.url!
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        let (data, _) = try await URLSession.shared.data(for: request)
        let days = try parse(data)
        guard !days.isEmpty else { throw Failure.noData }
        return DestinationWeather(source: range.source, days: days, clamped: range.clamped)
    }

    private struct Response: Decodable {
        struct Daily: Decodable {
            var time: [String]
            var temperature_2m_max: [Double?]
            var temperature_2m_min: [Double?]
            var precipitation_sum: [Double?]?
            var weather_code: [Int?]?
            var precipitation_probability_max: [Double?]?
        }
        var daily: Daily?
    }

    static func parse(_ data: Data) throws -> [DestinationWeather.Day] {
        guard let daily = try JSONDecoder().decode(Response.self, from: data).daily else { return [] }
        return daily.time.indices.compactMap { i in
            guard let date = WeatherWindow.day(daily.time[i]),
                  let high = daily.temperature_2m_max[safe: i] ?? nil,
                  let low = daily.temperature_2m_min[safe: i] ?? nil
            else { return nil }
            return DestinationWeather.Day(
                date: date,
                highC: high,
                lowC: low,
                precipMM: (daily.precipitation_sum?[safe: i] ?? nil) ?? 0,
                precipChance: (daily.precipitation_probability_max?[safe: i] ?? nil).map { $0 / 100 },
                code: (daily.weather_code?[safe: i] ?? nil) ?? 0
            )
        }
    }
}

/// WMO weather codes as Open-Meteo reports them.
enum WeatherCode {
    /// Collapses codes into clear, cloudy, fog, rain, snow, storm.
    static func group(_ code: Int) -> Int {
        switch code {
        case 0, 1: 0
        case 2, 3: 2
        case 45, 48: 45
        case 51...67, 80...82: 61
        case 71...77, 85, 86: 71
        case 95...99: 95
        default: 2
        }
    }

    static func symbol(_ code: Int) -> String {
        switch group(code) {
        case 0: "sun.max"
        case 45: "cloud.fog"
        case 61: "cloud.rain"
        case 71: "cloud.snow"
        case 95: "cloud.bolt.rain"
        default: code == 2 ? "cloud.sun" : "cloud"
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
