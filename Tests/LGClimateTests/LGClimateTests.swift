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

    func testJetUsesPowerFanAndHidesItFromRegularSpeeds() throws {
        let profile = DeviceProfile(json: .object(["property": .object([
            "airFlow": .object(["windStrength": spec(type: "enum", values: [.string("LOW"), .string("HIGH"), .string("POWER")])])
        ])]))
        let unit = makeUnit(profile: profile, state: ["airFlow": .object(["windStrength": .string("POWER")])])

        XCTAssertEqual(unit.fans, ["LOW", "HIGH"])
        XCTAssertTrue(unit.jetModeEnabled)
        XCTAssertEqual(unit.jetControl, FeatureToggle(resource: "airFlow", property: "windStrength", onValue: .string("POWER"), offValue: .string("HIGH")))
    }

    func testDedicatedTurboAndPowerSaveControls() throws {
        let profile = DeviceProfile(json: .object(["property": .object([
            "turbo": .object(["turboEnabled": spec(type: "boolean", values: [])]),
            "powerSave": .object(["powerSaveEnabled": spec(type: "boolean", values: [])])
        ])]))
        let unit = makeUnit(profile: profile, state: [
            "turbo": .object(["turboEnabled": .bool(true)]),
            "powerSave": .object(["powerSaveEnabled": .bool(true)])
        ])

        XCTAssertTrue(unit.jetModeEnabled)
        XCTAssertTrue(unit.energyControlEnabled)
        XCTAssertEqual(unit.jetControl?.resource, "turbo")
        XCTAssertEqual(unit.energyControl?.property, "powerSaveEnabled")
    }

    func testEnergySavingJobModeFallback() throws {
        let profile = DeviceProfile(json: .object(["property": .object([
            "airConJobMode": .object(["currentJobMode": spec(type: "enum", values: [.string("COOL"), .string("ENERGY_SAVING")])])
        ])]))
        let unit = makeUnit(profile: profile, state: [
            "airConJobMode": .object(["currentJobMode": .string("ENERGY_SAVING")])
        ])

        XCTAssertEqual(unit.mode, .cool)
        XCTAssertTrue(unit.energyControlEnabled)
        XCTAssertEqual(unit.energyControl?.onValue, .string("ENERGY_SAVING"))
    }

    func testDetailedFanAndOfficialSwingNames() throws {
        let profile = DeviceProfile(json: .object(["property": .object([
            "airFlow": .object(["windStrengthDetail": spec(type: "enum", values: [.string("LOW_MID"), .string("MID_HIGH")])]),
            "windDirection": .object([
                "windRotateUpDown": spec(type: "boolean", values: []),
                "windRotateLeftRight": spec(type: "boolean", values: [])
            ])
        ])]))
        let unit = makeUnit(profile: profile, state: [
            "airFlow": .object(["windStrengthDetail": .string("MID_HIGH")]),
            "windDirection": .object([
                "windRotateUpDown": .bool(true),
                "windRotateLeftRight": .bool(false)
            ])
        ])

        XCTAssertEqual(unit.fanProperty, "windStrengthDetail")
        XCTAssertEqual(unit.fan, "MID_HIGH")
        XCTAssertEqual(unit.fans, ["LOW_MID", "MID_HIGH"])
        XCTAssertEqual(unit.verticalSwingProperty, "windRotateUpDown")
        XCTAssertEqual(unit.horizontalSwingProperty, "windRotateLeftRight")
        XCTAssertEqual(unit.verticalSwing, true)
        XCTAssertEqual(unit.horizontalSwing, false)
    }

    private func makeUnit(profile: DeviceProfile, state: [String: JSONValue]) -> AirConditioner {
        let device = DeviceSummary(json: .object(["deviceId": .string("1"), "deviceInfo": .object(["alias": .string("Office"), "modelName": .string("RAC")])]))!
        return AirConditioner(summary: device, profile: profile, state: state, error: nil)
    }

    private func spec(type: String, values: [JSONValue]) -> JSONValue {
        .object(["type": .string(type), "mode": .array([.string("r"), .string("w")]), "value": .object(["w": .array(values)])])
    }
}
