import Foundation

enum RuleFreshness {
    static func isStale(_ isoDate: String) -> Bool {
        daysSinceVerified(isoDate) > 30
    }

    static func daysSinceVerified(_ isoDate: String) -> Int {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withDashSeparatorInDate]
        let date = formatter.date(from: String(isoDate.prefix(10)))
            ?? ISO8601DateFormatter().date(from: isoDate)
            ?? Date.distantPast
        return max(0, Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0)
    }
}
