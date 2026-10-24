public struct Trip: Codable, Sendable, Equatable {
    public var id: String?           // slug, e.g. "sfo-del"; names fixture plans
    public var from: String          // IATA airport, e.g. "SFO"
    public var to: String            // IATA airport, e.g. "DEL"
    public var airline: String       // IATA airline, e.g. "UA"
    public var nights: Int
    public var activities: [String]
    public var carryOn: Container
    public var checked: Container
    public var departDate: String?   // ISO date for the weather forecast

    public init(
        id: String? = nil, from: String, to: String, airline: String, nights: Int,
        activities: [String], carryOn: Container, checked: Container, departDate: String? = nil
    ) {
        self.id = id
        self.from = from
        self.to = to
        self.airline = airline
        self.nights = nights
        self.activities = activities
        self.carryOn = carryOn
        self.checked = checked
        self.departDate = departDate
    }
}
