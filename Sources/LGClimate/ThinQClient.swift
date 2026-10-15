import Foundation

struct ThinQConfiguration: Codable, Sendable {
    var token: String
    var country: String
    var clientID: String
}

enum ThinQError: LocalizedError {
    case invalidCountry(String), server(Int, String), malformed
    var errorDescription: String? {
        switch self {
        case .invalidCountry(let code): "LG ThinQ does not recognize country code \(code)."
        case .server(let status, let message): "LG ThinQ (\(status)): \(message)"
        case .malformed: "LG ThinQ returned an unreadable response."
        }
    }
}

actor ThinQClient {
    private static let apiKey = "ZkVkqP9jq44HuWkbNX9EKzZmmn7ToPY3A4vQ4tY8"
    private let configuration: ThinQConfiguration
    private let session: URLSession
    private let baseURL: URL

    init(configuration: ThinQConfiguration, session: URLSession = .shared) throws {
        self.configuration = configuration
        self.session = session
        let country = configuration.country.uppercased()
        guard let region = Self.region(country) else { throw ThinQError.invalidCountry(country) }
        baseURL = URL(string: "https://api-\(region).lgthinq.com")!
    }

    func devices() async throws -> [DeviceSummary] {
        let response = try await request("devices")
        let list = response.array ?? response.object?["devices"]?.array ?? []
        return list.compactMap(DeviceSummary.init(json:))
    }

    func profile(deviceID: String) async throws -> DeviceProfile {
        DeviceProfile(json: try await request("devices/\(deviceID)/profile"))
    }

    func state(deviceID: String) async throws -> [String: JSONValue] {
        guard let object = try await request("devices/\(deviceID)/state").object else { throw ThinQError.malformed }
        return object
    }

    func control(deviceID: String, payload: [String: [String: JSONValue]]) async throws {
        _ = try await request("devices/\(deviceID)/control", method: "POST", body: try JSONEncoder().encode(payload))
    }

    private func request(_ path: String, method: String = "GET", body: Data? = nil) async throws -> JSONValue {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.timeoutInterval = 15
        request.setValue("Bearer \(configuration.token)", forHTTPHeaderField: "Authorization")
        request.setValue(configuration.country.uppercased(), forHTTPHeaderField: "x-country")
        request.setValue(Self.messageID(), forHTTPHeaderField: "x-message-id")
        request.setValue(configuration.clientID, forHTTPHeaderField: "x-client-id")
        request.setValue(Self.apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("OP", forHTTPHeaderField: "x-service-phase")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ThinQError.malformed }
        let root = try JSONDecoder().decode(JSONValue.self, from: data)
        let object = root.object ?? [:]
        if !(200..<300).contains(http.statusCode) || object["error"] != nil {
            let error = object["error"]?.object
            let message = error?["message"]?.string ?? error?["code"]?.string ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw ThinQError.server(http.statusCode, message)
        }
        return object["response"] ?? root
    }

    private static func messageID() -> String {
        var tuple = UUID().uuid
        let data = withUnsafeBytes(of: &tuple) { Data($0) }
        return data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    private static func region(_ code: String) -> String? {
        let kic = Set("AU BD CN HK ID IN JP KH KR LA LK MM MY NP NZ PH SG TH TW VN".split(separator: " ").map(String.init))
        let aic = Set("AG AR AW BB BO BR BS BZ CA CL CO CR CU DM DO EC GD GT GY HN HT JM KN LC MX NI PA PE PR PY SR SV TT US UY VC VE".split(separator: " ").map(String.init))
        let eic = Set("AE AF AL AM AO AT AZ BA BE BF BG BH BJ BY CD CF CG CH CI CM CV CY CZ DE DJ DK DZ EE EG ES ET FI FR GA GB GE GH GM GN GQ GR HR HU IE IL IQ IR IS IT JO KE KG KW KZ LB LR LT LU LV LY MA MD ME MK ML MR MT MU MW NE NG NL NO OM PK PL PS PT QA RO RS RU RW SA SD SE SI SK SL SN SO ST SY TD TG TN TR TZ UA UG UZ XK YE ZA ZM".split(separator: " ").map(String.init))
        if kic.contains(code) { return "kic" }
        if aic.contains(code) { return "aic" }
        if eic.contains(code) { return "eic" }
        return nil
    }
}
