import Foundation
import PackFitSchemas

/// Typical travel items with their handling attributes, for identifying an item on the
/// device when the backend can't be reached. Sizes help pick between look-alikes (a
/// laptop and a book), but the measured size always stays the item's size (rule 6).
struct TravelCatalog: Sendable {
    struct Entry: Codable, Sendable, Equatable {
        var id: String
        var name: String
        var category: Category
        var kg: Double
        var fragile: Bool
        var soft: Bool
        var hardness: Double
        var upright: Bool
        var neededAtSecurity: Bool
        /// Typical size, cm, any order.
        var dims: [Double]
        var synonyms: [String]
    }

    struct Match: Sendable, Equatable {
        var entry: Entry
        var score: Double
    }

    let entries: [Entry]

    static let shared: TravelCatalog = {
        struct File: Decodable { var items: [Entry] }
        guard let url = Bundle.main.url(forResource: "travel_catalog", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data) else { return TravelCatalog(entries: []) }
        return TravelCatalog(entries: file.items)
    }()

    /// Entries ranked by how well the image labels (identifier, confidence) and the
    /// measured size agree with them. Labels are matched on whole words, so Vision's
    /// `running_shoe` matches "running shoe" and "shoe".
    func rank(labels: [(String, Double)], dimsCm: [Double]?) -> [Match] {
        let normalized = labels.map { (Self.words($0.0), $0.1) }
        var out: [Match] = []
        for entry in entries {
            var vision = 0.0
            for (label, conf) in normalized {
                let strength = entry.synonyms.map { Self.strength(label: label, synonym: Self.words($0)) }.max() ?? 0
                vision += conf * strength
            }
            guard vision > 0 else { continue }
            let fit = dimsCm.map { plausibility($0, entry.dims) } ?? 1
            out.append(Match(entry: entry, score: vision * (0.3 + 0.7 * fit)))
        }
        return out.sorted { $0.score != $1.score ? $0.score > $1.score : $0.entry.id < $1.entry.id }
    }

    /// Entries matching a typed name ("my running shoes"), best first.
    func rank(name: String) -> [Match] {
        let words = Self.words(name)
        guard !words.isEmpty else { return [] }
        return entries.compactMap { entry -> Match? in
            let s = entry.synonyms.map { Self.strength(label: words, synonym: Self.words($0)) }.max() ?? 0
            let byName = Self.strength(label: words, synonym: Self.words(entry.name))
            let score = max(s, byName)
            return score > 0 ? Match(entry: entry, score: score) : nil
        }
        .sorted { $0.score != $1.score ? $0.score > $1.score : $0.entry.id < $1.entry.id }
    }

    /// Entries whose typical size is closest to the measured one, for when the image
    /// gave nothing to go on.
    func rank(dimsCm: [Double]) -> [Match] {
        entries.map { Match(entry: $0, score: plausibility(dimsCm, $0.dims)) }
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.entry.id < $1.entry.id }
    }

    /// 1 when the sorted sizes match, falling off by a factor of 2 on the two big sides and
    /// a factor of 3 on the thickness, which varies most (a folded or stuffed item).
    func plausibility(_ measured: [Double], _ typical: [Double]) -> Double {
        guard measured.count == 3, typical.count == 3, measured.allSatisfy({ $0 > 0 }) else { return 0.5 }
        let m = measured.sorted(by: >), t = typical.sorted(by: >)
        let sigmas = [log(2.0), log(2.0), log(3.0)]
        var e = 0.0
        for i in 0..<3 {
            let r = log(m[i] / max(t[i], 0.1)) / sigmas[i]
            e += r * r
        }
        return exp(-e / 2)
    }

    /// Weight scaled with size for things that come in many sizes (clothes, food, bags);
    /// devices and documents weigh what they weigh.
    func kg(for entry: Entry, dimsCm: [Double]) -> Double {
        switch entry.category {
        case .electronics, .documents, .sharp, .medical:
            return entry.kg
        default:
            let v = dimsCm.reduce(1, *), tv = entry.dims.reduce(1, *)
            guard v > 0, tv > 0 else { return entry.kg }
            return (entry.kg * min(max(v / tv, 0.5), 2.5) * 100).rounded() / 100
        }
    }

    static func words(_ s: String) -> [String] {
        s.lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
    }

    /// 1 for the same words, 0.8 when the label holds every word of the synonym, 0.5 when
    /// a one-word label is part of the synonym ("shoe" for "running shoe").
    static func strength(label: [String], synonym: [String]) -> Double {
        guard !label.isEmpty, !synonym.isEmpty else { return 0 }
        if label == synonym { return 1 }
        func contains(_ a: [String], _ b: [String]) -> Bool {
            guard b.count <= a.count else { return false }
            return (0...(a.count - b.count)).contains { Array(a[$0..<$0 + b.count]) == b }
        }
        if contains(label, synonym) { return 0.8 }
        if label.count == 1, contains(synonym, label) { return 0.5 }
        return 0
    }
}
