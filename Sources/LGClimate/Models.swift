import Foundation

struct DeviceSummary: Identifiable, Sendable {
    let id: String
    let name: String
    let model: String
    let type: String

    init?(json: JSONValue) {
        guard let root = json.object else { return nil }
        let info = root["deviceInfo"]?.object ?? root
        guard let id = root["deviceId"]?.string ?? info["deviceId"]?.string else { return nil }
        self.id = id
        name = info["alias"]?.string ?? info["modelName"]?.string ?? "LG air conditioner"
        model = info["modelName"]?.string ?? "Unknown model"
        type = info["deviceType"]?.string ?? ""
    }
}

struct PropertySpec: Identifiable, Sendable {
    let resource: String
    let property: String
    let type: String
    let writable: Bool
    let values: [JSONValue]
    let min: Double?
    let max: Double?
    let step: Double?
    var id: String { "\(resource).\(property)" }
}

struct DeviceProfile: Sendable {
    let properties: [PropertySpec]

    init(json: JSONValue) {
        let root = json.object?["property"]?.object ?? json.object ?? [:]
        var output: [PropertySpec] = []
        for (resource, block) in root {
            let variants = block.array ?? [block]
            for variant in variants {
                guard let props = variant.object else { continue }
                for (property, raw) in props {
                    guard let spec = raw.object else { continue }
                    let modes = spec["mode"]?.array?.compactMap(\.string) ?? []
                    let write = spec["value"]?.object?["w"]
                    let range = write?.object
                    output.append(PropertySpec(resource: resource, property: property,
                        type: spec["type"]?.string ?? "", writable: modes.contains("w"),
                        values: write?.array ?? [], min: range?["min"]?.number,
                        max: range?["max"]?.number, step: range?["step"]?.number))
                }
            }
        }
        properties = output
    }

    func spec(_ resource: String, _ property: String) -> PropertySpec? {
        properties.first { $0.resource == resource && $0.property == property && $0.writable }
    }
}

enum ACMode: String, CaseIterable, Identifiable, Sendable {
    case auto = "AUTO", cool = "COOL", dry = "AIR_DRY", fan = "FAN", heat = "HEAT"
    var id: String { rawValue }
    var title: String { switch self { case .dry: "Dry"; default: rawValue.capitalized } }
    var symbol: String { switch self { case .auto: "a.circle"; case .cool: "snowflake"; case .dry: "drop"; case .fan: "fan"; case .heat: "sun.max" } }
}

struct AirConditioner: Identifiable, Sendable {
    let summary: DeviceSummary
    let profile: DeviceProfile
    var state: [String: JSONValue]
    var error: String?
    var id: String { summary.id }
    var name: String { summary.name }
    var model: String { summary.model }
    var isOnline: Bool { error == nil }
    var power: Bool { (state.value("operation", "airConOperationMode")?.string ?? "").uppercased().contains("ON") }
    var mode: ACMode? { state.value("airConJobMode", "currentJobMode")?.string.flatMap(ACMode.init(rawValue:)) }
    var currentTemperature: Double? { temperature(named: "currentTemperature") }
    var targetTemperature: Double? { temperature(named: "targetTemperature") ?? mode.flatMap { temperature(named: $0.rawValue.lowercased().replacingOccurrences(of: "air_dry", with: "dry") + "TargetTemperature") } }
    var fan: String? { state.value("airFlow", "windStrength")?.string }
    var verticalSwing: Bool? { state.value("windDirection", "rotateUpDown")?.bool }
    var horizontalSwing: Bool? { state.value("windDirection", "rotateLeftRight")?.bool }

    var modes: [ACMode] {
        guard let values = profile.spec("airConJobMode", "currentJobMode")?.values else { return [] }
        return values.compactMap { $0.string.flatMap(ACMode.init(rawValue:)) }
    }
    var fans: [String] { profile.spec("airFlow", "windStrength")?.values.compactMap(\.string) ?? [] }
    var temperatureSpec: PropertySpec? {
        let modeProperty: String? = switch mode {
        case .heat: "heatTargetTemperature"
        case .cool: "coolTargetTemperature"
        case .auto: "autoTargetTemperature"
        default: nil
        }
        return modeProperty.flatMap { profile.spec("temperature", $0) } ?? profile.spec("temperature", "targetTemperature")
    }

    private func temperature(named property: String) -> Double? {
        state.value("temperature", property)?.number
            ?? state.value("temperatureInUnits", property)?.number
            ?? state.value("temperature", property + "C")?.number
    }

    mutating func apply(resource: String, property: String, value: JSONValue) {
        if case .object(var block) = state[resource] { block[property] = value; state[resource] = .object(block) }
        else { state[resource] = .object([property: value]) }
    }
}

struct TimerRecord: Codable, Sendable {
    let deviceID: String
    let action: String
    let ends: Date
}
