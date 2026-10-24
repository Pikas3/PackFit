import Foundation
import ImageIO
import PackFitSchemas
import Vision

/// Identifies items and checks rules without the backend: Vision's image classifier
/// matched against the bundled travel catalog, and the bundled rule records. Fewer items
/// recognised than Claude, so confidence is kept low and the user picks from the
/// alternatives; the backend replaces it whenever it can be reached.
struct OnDeviceAPIClient: APIClient, Sendable {
    let catalog: TravelCatalog
    let rules: LocalRules

    init(catalog: TravelCatalog = .shared, rules: LocalRules = .shared) {
        self.catalog = catalog
        self.rules = rules
    }

    func scanItem(imageBase64: String, measured: MeasuredDims?, reference: String?, hint: String?) async throws -> ScanItemResponse {
        let dims = measured.map { [$0.w, $0.h, $0.d] }
        var ranked: [TravelCatalog.Match] = []
        var fromImage = false
        if let hint, !hint.isEmpty {
            ranked = catalog.rank(name: hint)
        }
        if ranked.isEmpty, let labels = Self.classify(imageBase64), !labels.isEmpty {
            ranked = catalog.rank(labels: labels, dimsCm: dims)
            fromImage = true
        }
        let top = ranked.first
        let sizeOnly = dims.map { catalog.rank(dimsCm: $0) } ?? []
        let alternatives = (ranked.dropFirst() + sizeOnly)
            .map { ItemAlternative(name: $0.entry.name, category: $0.entry.category) }
            .reduce(into: [ItemAlternative]()) { acc, a in
                if !acc.contains(a), a.name != top?.entry.name { acc.append(a) }
            }
            .prefix(3)

        let size = dims ?? top?.entry.dims ?? [15, 10, 10]
        var item: Item
        if let top {
            let e = top.entry
            item = Item(
                id: UUID().uuidString, name: e.name, w: size[0], h: size[1], d: size[2],
                kg: catalog.kg(for: e, dimsCm: size), fragile: e.fragile, hardness: e.hardness,
                soft: e.soft, upright: e.upright, category: e.category,
                // A hint is the user's word; the image match is a guess.
                confidence: fromImage ? min(0.75, 0.4 + top.score) : 0.8,
                neededAtSecurity: e.neededAtSecurity ? true : nil, source: .scan
            )
        } else {
            item = Item(id: UUID().uuidString, name: hint?.isEmpty == false ? hint! : "Item",
                        w: size[0], h: size[1], d: size[2], kg: 0.3, category: .other, confidence: 0.3, source: .scan)
        }
        if let measured {
            item.measurement = Measurement(method: measured.method, confidence: measured.confidence, deviceHasLidar: measured.method == .lidar)
        } else {
            item.measurement = Measurement(method: .catalog, confidence: 0.4, deviceHasLidar: false)
        }
        var warnings = ["identified_on_device"]
        if top == nil { warnings.append("not_recognised") }
        if let top, let dims, catalog.plausibility(dims, top.entry.dims) < 0.1 { warnings.append("dims_implausible_for_item") }
        return ScanItemResponse(item: item, alternatives: Array(alternatives), warnings: warnings)
    }

    func checkRules(items: [Item], trip: Trip, bag: String) async throws -> RulesCheckResponse {
        let flags = rules.flags(for: items, trip: trip, bag: bag)
        let banned = flags.filter { $0.severity == .banned }.count
        let summary = flags.isEmpty
            ? Copy.Rules.empty
            : "\(flags.count) flag\(flags.count == 1 ? "" : "s")\(banned > 0 ? ", \(banned) not allowed in this bag" : ""). \(Copy.Rules.guidance)"
        return RulesCheckResponse(
            flags: flags,
            summary: summary,
            stale: flags.contains { RuleFreshness.isStale($0.lastVerified) },
            rulesLastSynced: nil
        )
    }

    /// Vision's labels for the photo, most likely first. Nil if the image doesn't decode.
    static func classify(_ base64: String) -> [(String, Double)]? {
        let raw = base64.replacingOccurrences(of: #"^data:image/\w+;base64,"#, with: "", options: .regularExpression)
        guard let data = Data(base64Encoded: raw),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let request = VNClassifyImageRequest()
        do {
            try VNImageRequestHandler(cgImage: image, orientation: .up).perform([request])
        } catch {
            return nil
        }
        return (request.results ?? [])
            .filter { $0.confidence >= 0.02 }
            .prefix(25)
            .map { ($0.identifier, Double($0.confidence)) }
    }
}

/// The backend first; the device when it can't be reached or fails.
struct FallbackAPIClient: APIClient, Sendable {
    let primary: any APIClient
    let fallback: any APIClient

    func scanItem(imageBase64: String, measured: MeasuredDims?, reference: String?, hint: String?) async throws -> ScanItemResponse {
        do {
            return try await primary.scanItem(imageBase64: imageBase64, measured: measured, reference: reference, hint: hint)
        } catch {
            return try await fallback.scanItem(imageBase64: imageBase64, measured: measured, reference: reference, hint: hint)
        }
    }

    func checkRules(items: [Item], trip: Trip, bag: String) async throws -> RulesCheckResponse {
        do {
            return try await primary.checkRules(items: items, trip: trip, bag: bag)
        } catch {
            return try await fallback.checkRules(items: items, trip: trip, bag: bag)
        }
    }
}
