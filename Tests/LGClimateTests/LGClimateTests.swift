import XCTest
@testable import LGClimate

final class LGClimateTests: XCTestCase {
    func testProfileAndStateMapping() throws {
        let profile = DeviceProfile(json: .object(["property": .object([
            "operation": .object(["airConOperationMode": spec(type: "enum", values: [.string("POWER_ON"), .string("POWER_OFF")])]),
            "temperature": .object(["targetTemperature": .object([
                "type": .string("range"), "mode": .array([.string("r"), .string("w")]),
                "value": .object(["w": .object(["min": .number(18), "max": .number(30), "step": .number(0.5)])])
            ])])
        ])]))
        XCTAssertEqual(profile.spec("temperature", "targetTemperature")?.step, 0.5)
        let device = DeviceSummary(json: .object(["deviceId": .string("1"), "deviceInfo": .object(["alias": .string("Office"), "modelName": .string("RAC")])]))!
        let unit = AirConditioner(summary: device, profile: profile, state: [
            "operation": .object(["airConOperationMode": .string("POWER_ON")]),
            "temperature": .object(["targetTemperature": .number(22.5), "currentTemperature": .number(25)])
        ], error: nil)
        XCTAssertTrue(unit.power)
        XCTAssertEqual(unit.targetTemperature, 22.5)
        XCTAssertEqual(unit.currentTemperature, 25)
    }

    private func spec(type: String, values: [JSONValue]) -> JSONValue {
        .object(["type": .string(type), "mode": .array([.string("r"), .string("w")]), "value": .object(["w": .array(values)])])
    }
}
