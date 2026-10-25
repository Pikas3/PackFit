import Foundation

/// Where to put an item based on the strongest rule flag (guidance only).
enum PackAdvice: String, Sendable {
    case carryOnOnly = "Carry-on only"
    case checkedOnly = "Checked only"
    case doNotPack = "Do not pack"
    case ok = "OK to pack"

    static func forFlags(_ flags: [RuleFlag]) -> PackAdvice {
        if flags.contains(where: { $0.severity == .banned }) { return .doNotPack }
        let texts = flags.map(\.text).joined(separator: " ").lowercased()
        if texts.contains("carry-on") && (texts.contains("not allowed") || texts.contains("checked")) {
            return .checkedOnly
        }
        if texts.contains("checked") && texts.contains("banned") { return .carryOnOnly }
        if flags.contains(where: { $0.severity == .restricted }) { return .checkedOnly }
        if flags.contains(where: { $0.severity == .check }) { return .ok }
        return .ok
    }
}
