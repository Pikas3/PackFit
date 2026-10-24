import Foundation

struct AppConfig: Sendable {
    var apiBaseURL: URL
    var appToken: String
    var mockAPI: Bool

    static let shared: AppConfig = {
        let info = Bundle.main.infoDictionary ?? [:]
        let base = (info["API_BASE_URL"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = URL(string: base ?? "http://localhost:8787") ?? URL(string: "http://localhost:8787")!
        let token = (info["APP_TOKEN"] as? String) ?? "local-dev-token"
        let mockRaw = (info["MOCK_API"] as? String)?.uppercased() ?? "YES"
        let mock = mockRaw == "YES" || mockRaw == "1" || mockRaw == "TRUE"
        return AppConfig(apiBaseURL: url, appToken: token, mockAPI: mock)
    }()
}
