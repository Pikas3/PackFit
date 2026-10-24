public enum ItemSource: String, Codable, Sendable { case scan, manual, suggested, fixture }

public struct Item: Codable, Identifiable, Sendable, Equatable {
    public var id: String                // uuid
    public var name: String
    public var w: Double                 // width, cm, as scanned (before orientation)
    public var h: Double                 // height, cm
    public var d: Double                 // depth, cm
    public var kg: Double
    public var fragile: Bool             // never place anything on top of it
    public var hardness: Double          // 0 (plush) to 1 (rigid)
    public var soft: Bool                // may compress 20% in the packer
    public var upright: Bool             // orientation locked: h stays vertical
    public var category: Category
    public var confidence: Double        // 0-1, overall; 1 for manual/fixture items
    public var neededAtSecurity: Bool?   // packer puts these on top
    public var source: ItemSource?
    public var measurement: Measurement?

    public init(
        id: String, name: String, w: Double, h: Double, d: Double, kg: Double,
        fragile: Bool = false, hardness: Double = 0.5, soft: Bool = false, upright: Bool = false,
        category: Category = .other, confidence: Double = 1,
        neededAtSecurity: Bool? = nil, source: ItemSource? = nil, measurement: Measurement? = nil
    ) {
        self.id = id
        self.name = name
        self.w = w
        self.h = h
        self.d = d
        self.kg = kg
        self.fragile = fragile
        self.hardness = hardness
        self.soft = soft
        self.upright = upright
        self.category = category
        self.confidence = confidence
        self.neededAtSecurity = neededAtSecurity
        self.source = source
        self.measurement = measurement
    }
}
