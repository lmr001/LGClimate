import AppKit
import SwiftUI

@MainActor
final class AppStore: ObservableObject {
    @Published var units: [AirConditioner] = []
    @Published var selectedID: String?
    @Published var connected = false
    @Published var busy = false
    @Published var pending: Set<String> = []
    @Published var error: String?
    @Published var lastUpdated: Date?
    @Published var token = ""
    @Published var country = "ZA"
    @Published var remember = true
    @Published var timer: TimerRecord?
    private var client: ThinQClient?
    private var refreshTask: Task<Void, Never>?

    var selected: AirConditioner? {
        get { units.first { $0.id == selectedID } ?? units.first }
        set {
            guard let value = newValue, let index = units.firstIndex(where: { $0.id == value.id }) else { return }
            units[index] = value
        }
    }

    func restore() async {
        guard !connected, !busy else { return }
        do {
            guard let saved = try Credentials.load() else { return }
            token = saved.token
            country = saved.country
            await connect(configuration: saved, save: false)
        } catch { self.error = error.localizedDescription }
    }

    func connect() async {
        let cleaned = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let code = country.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !cleaned.isEmpty, code.count == 2 else { error = "Enter your LG Personal Access Token and two-letter account country code."; return }
        let savedID = UserDefaults.standard.string(forKey: "thinQClientID")
        let clientID = savedID ?? UUID().uuidString
        UserDefaults.standard.set(clientID, forKey: "thinQClientID")
        await connect(configuration: ThinQConfiguration(token: cleaned, country: code, clientID: clientID), save: remember)
    }

    private func connect(configuration: ThinQConfiguration, save: Bool) async {
        busy = true
        error = nil
        do {
            let candidate = try ThinQClient(configuration: configuration)
            client = candidate
            let loaded = try await loadUnits(using: candidate)
            units = loaded
            selectedID = selectedID ?? loaded.first?.id
            connected = true
            lastUpdated = Date()
            if save { try Credentials.save(configuration) }
            startPolling()
        } catch { self.error = friendly(error); client = nil }
        busy = false
    }

    func refresh() async {
        guard let client, connected, !busy else { return }
        busy = true
        do {
            let loaded = try await loadUnits(using: client)
            units = loaded
            if !loaded.contains(where: { $0.id == selectedID }) { selectedID = loaded.first?.id }
            lastUpdated = Date()
            error = nil
        } catch { self.error = friendly(error) }
        busy = false
    }

    private func loadUnits(using client: ThinQClient) async throws -> [AirConditioner] {
        let devices = try await client.devices().filter { $0.type.contains("AIR_CONDITIONER") || $0.type.isEmpty }
        var result: [AirConditioner] = []
        for device in devices {
            do {
                async let profile = client.profile(deviceID: device.id)
                async let state = client.state(deviceID: device.id)
                result.append(try await AirConditioner(summary: device, profile: profile, state: state, error: nil))
            } catch {
                let profile = (try? await client.profile(deviceID: device.id)) ?? DeviceProfile(json: .object([:]))
                result.append(AirConditioner(summary: device, profile: profile, state: [:], error: friendly(error)))
            }
        }
        return result
    }

    func setPower(_ on: Bool) { send(resource: "operation", property: "airConOperationMode", value: .string(on ? "POWER_ON" : "POWER_OFF")) }
    func setMode(_ mode: ACMode) { send(resource: "airConJobMode", property: "currentJobMode", value: .string(mode.rawValue)) }
    func setFan(_ fan: String) { send(resource: "airFlow", property: "windStrength", value: .string(fan)) }
    func setJetMode(_ on: Bool) {
        guard let control = selected?.jetControl else { return }
        send(resource: control.resource, property: control.property, value: on ? control.onValue : control.offValue)
    }
    func setEnergyControl(_ on: Bool) {
        guard let control = selected?.energyControl else { return }
        send(resource: control.resource, property: control.property, value: on ? control.onValue : control.offValue)
    }
    func setSwing(vertical: Bool, on: Bool) { send(resource: "windDirection", property: vertical ? "rotateUpDown" : "rotateLeftRight", value: .bool(on)) }
    func setTemperature(_ value: Double) {
        guard let unit = selected, let spec = unit.temperatureSpec else { return }
        let step = spec.step ?? 0.5
        let snapped = (value / step).rounded() * step
        guard snapped >= (spec.min ?? 16), snapped <= (spec.max ?? 30) else { return }
        send(resource: "temperature", property: spec.property, value: .number(snapped))
    }

    func setTimer(minutes: Int) {
        guard let unit = selected, minutes > 0 else { return }
        let action = unit.power ? "stop" : "start"
        let prefix = unit.power ? "Stop" : "Start"
        let payload: [String: [String: JSONValue]] = ["timer": [
            "relativeHourTo\(prefix)": .number(Double(minutes / 60)),
            "relativeMinuteTo\(prefix)": .number(Double(minutes % 60))
        ]]
        deliver(payload, optimistic: nil) { [weak self] in
            self?.timer = TimerRecord(deviceID: unit.id, action: action, ends: Date().addingTimeInterval(Double(minutes * 60)))
        }
    }

    func cancelTimer() {
        guard let unit = selected else { return }
        let property = unit.power ? "relativeStopTimer" : "relativeStartTimer"
        deliver(["timer": [property: .string("UNSET")]], optimistic: nil) { [weak self] in self?.timer = nil }
    }

    private func send(resource: String, property: String, value: JSONValue) {
        guard var unit = selected, unit.isOnline else { return }
        unit.apply(resource: resource, property: property, value: value)
        selected = unit
        deliver([resource: [property: value]], optimistic: unit, completion: nil)
    }

    private func deliver(_ payload: [String: [String: JSONValue]], optimistic: AirConditioner?, completion: (() -> Void)?) {
        guard let client, let unit = selected else { return }
        pending.insert(unit.id)
        error = nil
        Task {
            do {
                try await client.control(deviceID: unit.id, payload: payload)
                completion?()
                try? await Task.sleep(for: .seconds(2.5))
                let reported = try await client.state(deviceID: unit.id)
                if var current = units.first(where: { $0.id == unit.id }) { current.state = reported; current.error = nil; selected = current }
                lastUpdated = Date()
            } catch {
                self.error = friendly(error)
                if optimistic != nil { await refresh() }
            }
            pending.remove(unit.id)
        }
    }

    func signOut() {
        try? Credentials.delete()
        refreshTask?.cancel()
        client = nil
        units = []
        selectedID = nil
        token = ""
        connected = false
        error = nil
    }

    private func startPolling() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                await self?.refresh()
            }
        }
    }

    private func friendly(_ error: Error) -> String {
        if case ThinQError.server(let status, _) = error, status == 401 || status == 403 {
            return "LG rejected the token. Generate a new PAT at connect-pat.lgthinq.com and confirm the account country."
        }
        return error.localizedDescription
    }
}
