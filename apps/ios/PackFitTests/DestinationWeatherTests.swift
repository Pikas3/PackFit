import Foundation
import Testing
@testable import PackFit

struct DestinationWeatherTests {
    private let today = WeatherWindow.day("2026-10-25")!

    @Test func soonTripUsesTheForecast() {
        let range = WeatherWindow.range(departDate: "2026-10-28", nights: 5, today: today)
        #expect(range == .init(source: .forecast, start: "2026-10-28", end: "2026-11-02", clamped: false))
    }

    @Test func forecastStopsAtSixteenDays() {
        let range = WeatherWindow.range(departDate: "2026-11-05", nights: 14, today: today)
        #expect(range == .init(source: .forecast, start: "2026-11-05", end: "2026-11-09", clamped: true))
    }

    @Test func farTripUsesLastYear() {
        let range = WeatherWindow.range(departDate: "2026-12-15", nights: 21, today: today)
        #expect(range == .init(source: .lastYear, start: "2025-12-15", end: "2026-01-05", clamped: false))
    }

    @Test func lastYearNeverAsksPastTheArchive() {
        // Last year's dates would end after the archive does, so it goes back two years.
        let range = WeatherWindow.range(departDate: "2027-10-20", nights: 30, today: today)
        #expect(range?.source == .lastYear)
        #expect(range?.start == "2025-10-20")
    }

    @Test func parsesDailyAndSkipsMissingDays() throws {
        let json = """
        {"daily":{"time":["2026-10-28","2026-10-29","2026-10-30"],
          "temperature_2m_max":[24.1,null,26.0],"temperature_2m_min":[12.0,11.0,13.5],
          "precipitation_sum":[0,3.2,0.4],"weather_code":[0,61,2],
          "precipitation_probability_max":[5,80,60]}}
        """
        let days = try WeatherClient.parse(Data(json.utf8))
        #expect(days.count == 2)
        let weather = DestinationWeather(source: .forecast, days: days, clamped: false)
        #expect(weather.highC == 26.0)
        #expect(weather.lowC == 12.0)
        #expect(weather.wetDays == 1)
    }

    @Test func typicalWeatherIsTheMostCommon() {
        func day(_ code: Int) -> DestinationWeather.Day {
            .init(date: .now, highC: 20, lowC: 10, precipMM: 0, precipChance: nil, code: code)
        }
        let weather = DestinationWeather(source: .forecast, days: [day(0), day(1), day(61)], clamped: false)
        #expect(WeatherCode.symbol(weather.typicalCode) == "sun.max")
    }
}
