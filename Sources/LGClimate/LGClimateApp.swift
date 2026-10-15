import AppKit
import SwiftUI

private enum UITheme {
    static let width: CGFloat = 336
    static let secondary = Color.white.opacity(0.55)
    static func accent(_ mode: ACMode?) -> Color {
        switch mode {
        case .heat: Color(red: 1.00, green: 0.58, blue: 0.28)
        case .dry: Color(red: 0.35, green: 0.84, blue: 0.76)
        case .auto: Color(red: 0.67, green: 0.60, blue: 1.00)
        case .fan: Color(red: 0.70, green: 0.78, blue: 0.84)
        default: Color(red: 0.25, green: 0.62, blue: 1.00)
        }
    }
}

@main
struct LGClimateApp: App {
    @StateObject private var store = AppStore()
    var body: some Scene {
        MenuBarExtra {
            ClimatePanel(store: store).task { await store.restore() }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "snowflake")
                if let temperature = store.selected?.currentTemperature { Text(formatTemperature(temperature) + "°") }
            }.accessibilityLabel("LG Climate")
        }.menuBarExtraStyle(.window)
    }
}

private struct ClimatePanel: View {
    @ObservedObject var store: AppStore
    @State private var showingSettings = false
    var body: some View {
        Group {
            if !store.connected || showingSettings {
                ConnectionView(store: store, canGoBack: store.connected) { showingSettings = false }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else if store.units.isEmpty {
                EmptyView(store: store)
            } else {
                ControlsView(store: store) { showingSettings = true }
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .padding(14)
        .frame(width: UITheme.width)
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .background(Color(white: 0.105))
        .animation(.snappy(duration: 0.28), value: showingSettings)
    }
}

private struct ControlsView: View {
    @ObservedObject var store: AppStore
    let showSettings: () -> Void
    @State private var draggingTarget: Double?
    private var unit: AirConditioner? { store.selected }
    private var isPending: Bool { unit.map { store.pending.contains($0.id) } ?? false }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let unit {
                header(unit)
                Divider()
                targetAndUnit(unit)
                temperatureSlider(unit)
                Divider()
                modeControl(unit)
                fanControl(unit)
                Divider()
                specialModeRows(unit)
                if supportsSwing(unit) { Divider(); swingRows(unit) }
                Divider()
                timerRow(unit)
                MenuRow(title: "LG Climate settings…", badge: store.error != nil, action: showSettings)
            }
        }
    }

    private func header(_ unit: AirConditioner) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                if store.units.count > 1 {
                    Menu {
                        ForEach(store.units) { item in Button(item.name) { store.selectedID = item.id } }
                    } label: {
                        HStack(spacing: 4) { Text(unit.name); Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .bold)).foregroundStyle(UITheme.secondary) }
                    }.menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
                } else { Text(unit.name).font(.system(size: 13, weight: .semibold)) }
                if let error = unit.error { Text(error).lineLimit(1).foregroundStyle(.orange) }
                else if isPending { Text("Syncing with LG ThinQ…") }
                else { Text("Room · \(formatTemperature(unit.currentTemperature)) °C") }
            }
            .font(.system(size: 12)).foregroundStyle(UITheme.secondary)
            Spacer()
            Button { haptic(); store.setPower(!unit.power) } label: {
                Image(systemName: "power").font(.system(size: 12, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .foregroundStyle(unit.power ? Color(white: 0.12) : UITheme.secondary)
                    .background(unit.power ? Color.white : Color.white.opacity(0.08), in: Circle())
                    .overlay { if isPending { Circle().trim(from: 0.12, to: 0.72).stroke(UITheme.accent(unit.mode), style: StrokeStyle(lineWidth: 2, lineCap: .round)).rotationEffect(.degrees(90)) } }
                    .animation(.snappy, value: unit.power)
            }
            .buttonStyle(.plain).disabled(!unit.isOnline || isPending)
            .help(unit.power ? "Turn off" : "Turn on")
            .accessibilityLabel(unit.power ? "Turn off \(unit.name)" : "Turn on \(unit.name)")
        }
    }

    private func targetAndUnit(_ unit: AirConditioner) -> some View {
        VStack(spacing: 2) {
            AnimatedACUnit(unit: unit).frame(maxWidth: .infinity).frame(height: 128)
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    TargetTemperature(value: draggingTarget ?? unit.targetTemperature).opacity(unit.power ? 1 : 0.38)
                    Text(activity(unit, target: draggingTarget ?? unit.targetTemperature))
                        .font(.system(size: 12)).foregroundStyle(UITheme.secondary).contentTransition(.interpolate)
                }
                Spacer()
                if let room = unit.currentTemperature {
                    Label("\(formatTemperature(room))°C indoors", systemImage: "thermometer.medium")
                        .font(.system(size: 11)).foregroundStyle(UITheme.secondary)
                }
            }
        }
    }

    @ViewBuilder private func temperatureSlider(_ unit: AirConditioner) -> some View {
        if let spec = unit.temperatureSpec {
            TemperatureSlider(value: unit.targetTemperature ?? spec.min ?? 18,
                range: (spec.min ?? 16)...(spec.max ?? 30), step: spec.step ?? 0.5,
                accent: UITheme.accent(unit.mode), onChange: { draggingTarget = $0 },
                onCommit: { draggingTarget = nil; store.setTemperature($0) })
                .disabled(!unit.power || isPending).opacity(unit.power ? 1 : 0.38)
        }
    }

    private func modeControl(_ unit: AirConditioner) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("MODE").font(.system(size: 10, weight: .semibold)).foregroundStyle(UITheme.secondary)
            HStack(spacing: 0) {
                ForEach(unit.modes) { mode in
                    Button { store.setMode(mode) } label: {
                        VStack(spacing: 3) { Image(systemName: mode.symbol).font(.system(size: 12)); Text(mode.title).font(.system(size: 10, weight: .medium)) }
                            .frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.plain).foregroundStyle(unit.mode == mode ? .white : UITheme.secondary)
                    .background(unit.mode == mode ? UITheme.accent(mode).opacity(0.48) : .clear)
                }
            }
            .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous)).disabled(!unit.power || isPending)
        }
    }

    private func fanControl(_ unit: AirConditioner) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("FAN SPEED").font(.system(size: 10, weight: .semibold)).foregroundStyle(UITheme.secondary)
            if unit.fans.isEmpty {
                HStack {
                    Image(systemName: "fan").font(.system(size: 11))
                    Text("Unavailable").font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(UITheme.secondary).frame(maxWidth: .infinity).padding(.vertical, 9)
                .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            } else if unit.fans.count <= 5 {
                HStack(spacing: 0) {
                    ForEach(unit.fans, id: \.self) { fanButton($0, unit: unit) }
                }
                .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 4), spacing: 0) {
                    ForEach(unit.fans, id: \.self) { fanButton($0, unit: unit) }
                }
                .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
        }
        .disabled(!unit.power || isPending)
        .opacity(unit.power ? 1 : 0.4)
    }

    private func fanButton(_ speed: String, unit: AirConditioner) -> some View {
        let selected = unit.fan?.uppercased() == speed.uppercased()
        return Button { store.setFan(speed) } label: {
            VStack(spacing: 3) {
                Image(systemName: fanSymbol(speed)).font(.system(size: 12))
                Text(fanTitle(speed)).font(.system(size: 9.5, weight: .medium)).lineLimit(1).minimumScaleFactor(0.72)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .foregroundStyle(selected ? .white : UITheme.secondary)
        .background(selected ? UITheme.accent(unit.mode).opacity(0.48) : .clear)
        .accessibilityLabel("\(fanTitle(speed)) fan speed")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func specialModeRows(_ unit: AirConditioner) -> some View {
        VStack(spacing: 10) {
            if let _ = unit.jetControl {
                CircleToggleRow(icon: "bolt.fill", title: "Jet mode", on: unit.jetModeEnabled) {
                    store.setJetMode(!unit.jetModeEnabled)
                }
                .disabled(unit.mode != .cool && unit.mode != .heat)
                .help("Rapid cooling or heating at maximum airflow")
            } else {
                UnavailableFeatureRow(icon: "bolt.fill", title: "Jet mode")
                    .help("This air conditioner's ThinQ profile does not report a Jet control")
            }
            if let _ = unit.energyControl {
                CircleToggleRow(icon: "leaf.fill", title: "Energy control", on: unit.energyControlEnabled) {
                    store.setEnergyControl(!unit.energyControlEnabled)
                }
                .disabled(unit.mode != .cool)
                .help("Reduce power use while cooling")
            } else {
                UnavailableFeatureRow(icon: "leaf.fill", title: "Energy control")
                    .help("This air conditioner's ThinQ profile does not report an Energy control")
            }
        }
        .disabled(!unit.power || isPending)
        .opacity(unit.power ? 1 : 0.4)
    }

    private func swingRows(_ unit: AirConditioner) -> some View {
        VStack(spacing: 10) {
            if unit.profile.spec("windDirection", "rotateUpDown") != nil {
                CircleToggleRow(icon: "arrow.up.and.down", title: "Up / down swing", on: unit.verticalSwing ?? false) { store.setSwing(vertical: true, on: !(unit.verticalSwing ?? false)) }
            }
            if unit.profile.spec("windDirection", "rotateLeftRight") != nil {
                CircleToggleRow(icon: "arrow.left.and.right", title: "Side-to-side swing", on: unit.horizontalSwing ?? false) { store.setSwing(vertical: false, on: !(unit.horizontalSwing ?? false)) }
            }
        }.disabled(!unit.power || isPending).opacity(unit.power ? 1 : 0.4)
    }

    private func timerRow(_ unit: AirConditioner) -> some View {
        HStack {
            Label(store.timer?.deviceID == unit.id ? (store.timer?.action == "stop" ? "Turns off" : "Turns on") : "Timer", systemImage: "timer").font(.system(size: 13))
            if let timer = store.timer, timer.deviceID == unit.id { Text(timer.ends, style: .timer).font(.caption).monospacedDigit().foregroundStyle(UITheme.secondary) }
            Spacer()
            Menu(store.timer?.deviceID == unit.id ? "Change" : "Set") {
                Button("30 minutes") { store.setTimer(minutes: 30) }; Button("1 hour") { store.setTimer(minutes: 60) }
                Button("2 hours") { store.setTimer(minutes: 120) }; Button("4 hours") { store.setTimer(minutes: 240) }
                if store.timer?.deviceID == unit.id { Divider(); Button("Cancel timer", role: .destructive, action: store.cancelTimer) }
            }.menuStyle(.borderlessButton).fixedSize()
        }
    }

    private func supportsSwing(_ unit: AirConditioner) -> Bool {
        unit.profile.spec("windDirection", "rotateUpDown") != nil || unit.profile.spec("windDirection", "rotateLeftRight") != nil
    }

}

private struct TargetTemperature: View {
    let value: Double?
    var body: some View {
        let whole = value.map { String(Int($0.rounded(.down))) } ?? "—"
        let half = value.map { $0 != $0.rounded(.down) } ?? false
        HStack(alignment: .firstTextBaseline, spacing: 1) {
            Text(whole).font(.system(size: 46, weight: .medium, design: .rounded))
            if half { Text(".5").font(.system(size: 23, weight: .medium, design: .rounded)) }
            Text("°C").font(.system(size: 17)).foregroundStyle(UITheme.secondary)
        }.monospacedDigit().contentTransition(.numericText(value: value ?? 0))
    }
}

private struct TemperatureSlider: View {
    let value: Double; let range: ClosedRange<Double>; let step: Double; let accent: Color
    let onChange: (Double) -> Void; let onCommit: (Double) -> Void
    @State private var dragging: Double?
    var body: some View {
        VStack(spacing: 5) {
            GeometryReader { proxy in
                let thumb: CGFloat = 17, usable = proxy.size.width - thumb
                let x = thumb / 2 + usable * fraction(dragging ?? value)
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.09)).frame(height: 5)
                    Capsule().fill(LinearGradient(colors: [accent.opacity(0.4), accent], startPoint: .leading, endPoint: .trailing)).frame(width: x, height: 5)
                    Circle().fill(.white).frame(width: thumb, height: thumb).shadow(color: .black.opacity(0.4), radius: 3, y: 1).offset(x: x - thumb / 2).scaleEffect(dragging == nil ? 1 : 1.13)
                }.frame(maxHeight: .infinity).contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { e in let v = snapped(e.location.x, usable: usable, thumb: thumb); dragging = v; onChange(v) }.onEnded { e in let v = snapped(e.location.x, usable: usable, thumb: thumb); dragging = nil; onCommit(v) })
            }.frame(height: 27)
            HStack { Text("\(formatTemperature(range.lowerBound))°"); Spacer(); Text("\(formatTemperature(range.upperBound))°") }
                .font(.system(size: 10, weight: .medium)).foregroundStyle(UITheme.secondary).monospacedDigit()
        }
    }
    private func fraction(_ v: Double) -> Double { min(max((v - range.lowerBound) / (range.upperBound - range.lowerBound), 0), 1) }
    private func snapped(_ x: CGFloat, usable: CGFloat, thumb: CGFloat) -> Double {
        let f = min(max((x - thumb / 2) / usable, 0), 1), raw = range.lowerBound + f * (range.upperBound - range.lowerBound)
        return min(range.lowerBound + ((raw - range.lowerBound) / step).rounded() * step, range.upperBound)
    }
}

private struct AnimatedACUnit: View {
    let unit: AirConditioner
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var changedAt = Date.distantPast
    @State private var transitioning = false
    private static let ramp = 1.1

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion || (!unit.power && !transitioning))) { timeline in
            Canvas { canvas, size in draw(&canvas, size: size, now: timeline.date) }
        }
        .onChange(of: unit.power) { _, _ in
            changedAt = .now; transitioning = true
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.ramp + 0.15) { transitioning = false }
        }
        .accessibilityLabel(unit.power ? "Air conditioner running in \(unit.mode?.title ?? "current") mode" : "Air conditioner off")
    }

    private func draw(_ canvas: inout GraphicsContext, size: CGSize, now: Date) {
        let raw = reduceMotion ? 1 : min(1, now.timeIntervalSince(changedAt) / Self.ramp)
        let eased = raw < 0.5 ? 2 * raw * raw : 1 - pow(-2 * raw + 2, 2) / 2
        let level = unit.power ? eased : 1 - eased
        let time = reduceMotion ? 0.6 : now.timeIntervalSinceReferenceDate
        let ink = Color.white, accent = UITheme.accent(unit.mode)
        let width = min(size.width * 0.72, 222), height: CGFloat = 62
        let shell = CGRect(x: (size.width - width) / 2, y: 3, width: width, height: height)
        let shellPath = Path(roundedRect: shell, cornerRadius: 7, style: .continuous)
        let seamY = shell.maxY - 22

        canvas.fill(shellPath, with: .linearGradient(Gradient(colors: [ink.opacity(0.15), ink.opacity(0.045)]), startPoint: CGPoint(x: shell.midX, y: shell.minY), endPoint: CGPoint(x: shell.midX, y: shell.maxY)))
        canvas.stroke(shellPath, with: .color(ink.opacity(0.20 + 0.23 * level)), lineWidth: 1)
        var seam = Path(); seam.move(to: CGPoint(x: shell.minX, y: seamY)); seam.addLine(to: CGPoint(x: shell.maxX, y: seamY))
        canvas.stroke(seam, with: .color(ink.opacity(0.10)), lineWidth: 1)

        let display = CGRect(x: shell.maxX - 62, y: shell.minY + 14, width: 43, height: 16)
        canvas.fill(Path(roundedRect: display, cornerRadius: 4), with: .color(.black.opacity(0.30 + 0.30 * level)))
        if level > 0.02 {
            let text = "\(unit.mode == .cool ? "❄︎ " : "")\(formatTemperature(unit.targetTemperature))"
            var lit = canvas; lit.opacity = level
            lit.draw(Text(text).font(.system(size: 9, weight: .semibold).monospacedDigit()).foregroundStyle(accent), at: CGPoint(x: display.midX, y: display.midY))
        }

        let outlet = CGRect(x: shell.minX + 16, y: seamY + 6, width: width - 32, height: 10)
        let tiltWave = (unit.verticalSwing ?? false) ? (0.5 + 0.5 * sin(time * 1.15)) : 0.48
        let angle = level * (98 + 52 * tiltWave) * .pi / 180
        let hingeY = outlet.maxY
        let freeY = hingeY - outlet.height * cos(angle)
        let spread = 3 * sin(angle)
        let opening = CGRect(x: outlet.minX, y: outlet.minY, width: outlet.width, height: max(min(freeY, hingeY) - outlet.minY, 0))
        if level > 0.01 {
            canvas.fill(Path(roundedRect: opening, cornerRadius: 1.5), with: .linearGradient(Gradient(colors: [.black.opacity(0.58), .black.opacity(0.30)]), startPoint: CGPoint(x: 0, y: opening.minY), endPoint: CGPoint(x: 0, y: opening.maxY)))
            let lean: CGFloat = (unit.horizontalSwing ?? false) ? CGFloat(sin(time * 1.05) * 4) : 0
            var fins = Path(); var x = outlet.minX + 8
            while x <= outlet.maxX - 8 { fins.move(to: CGPoint(x: x, y: opening.minY + 1)); fins.addLine(to: CGPoint(x: x + lean, y: max(opening.maxY, opening.minY + 2))); x += 9 }
            canvas.stroke(fins, with: .color(ink.opacity(0.28 * level)), lineWidth: 0.8)
        }
        var flap = Path(); flap.move(to: CGPoint(x: outlet.minX, y: hingeY)); flap.addLine(to: CGPoint(x: outlet.maxX, y: hingeY)); flap.addLine(to: CGPoint(x: outlet.maxX + spread, y: freeY)); flap.addQuadCurve(to: CGPoint(x: outlet.minX - spread, y: freeY), control: CGPoint(x: outlet.midX, y: freeY + 2)); flap.closeSubpath()
        canvas.fill(flap, with: .linearGradient(Gradient(colors: [ink.opacity(0.07), ink.opacity(0.17)]), startPoint: CGPoint(x: 0, y: hingeY), endPoint: CGPoint(x: 0, y: freeY)))
        canvas.stroke(flap, with: .color(ink.opacity(0.18 + 0.34 * level)), lineWidth: 1)

        guard level > 0.01 else { return }
        let top = max(freeY, hingeY) + 5, depth = max(size.height - top - 2, 1)
        let speed: Double = switch unit.fan { case "HIGH": 1.45; case "LOW": 0.68; default: 1 }
        let lateral = (unit.horizontalSwing ?? false) ? sin(time * 1.05) * 0.28 : 0
        var cone = Path(); cone.move(to: CGPoint(x: outlet.minX + 5, y: top)); cone.addLine(to: CGPoint(x: outlet.maxX - 5, y: top)); cone.addLine(to: CGPoint(x: shell.midX + width * 0.61 + lateral * depth, y: top + depth)); cone.addLine(to: CGPoint(x: shell.midX - width * 0.61 + lateral * depth, y: top + depth)); cone.closeSubpath()
        canvas.drawLayer { glow in glow.addFilter(.blur(radius: 11)); glow.fill(cone, with: .linearGradient(Gradient(colors: [accent.opacity(0.11 * level), .clear]), startPoint: CGPoint(x: shell.midX, y: top), endPoint: CGPoint(x: shell.midX, y: top + depth))) }

        func point(_ lane: Double, _ progress: Double, _ seed: Double) -> CGPoint {
            let spread = lane * (width / 2 - 24) + lane * progress * width * 0.30
            let sway = sin(time * (unit.mode == .heat ? 2.6 : 1.6) + seed * 2.3 + progress * 4) * 3.8 * progress
            return CGPoint(x: shell.midX + spread + lateral * progress * depth + sway, y: top + progress * depth)
        }
        canvas.drawLayer { air in
            air.addFilter(.blur(radius: 0.55))
            for stream in 0..<11 {
                let lane = Double(stream) / 5 - 1
                for wisp in 0..<3 {
                    let seed = Double(stream * 7 + wisp * 13)
                    let cycle = (time * 0.42 * speed + Double(wisp) / 3 + sin(seed * 1.7) * 0.5).truncatingRemainder(dividingBy: 1)
                    let reach = 0.35 + 0.65 * level, head = cycle * reach, tail = max(0, head - 0.31 * reach)
                    guard head > 0.02 else { continue }
                    var path = Path(); path.move(to: point(lane, tail, seed)); for step in 1...9 { path.addLine(to: point(lane, tail + (head - tail) * Double(step) / 9, seed)) }
                    let alpha = sin(.pi * cycle) * (0.40 - abs(lane) * 0.10) * level
                    air.stroke(path, with: .linearGradient(Gradient(colors: [.clear, accent.opacity(alpha), accent.opacity(alpha * 0.45)]), startPoint: point(lane, tail, seed), endPoint: point(lane, head, seed)), style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round))
                }
            }
        }
    }
}

private struct CircleToggleRow: View {
    let icon: String; let title: String; let on: Bool; let action: () -> Void
    var body: some View {
        Button(action: action) { HStack { Image(systemName: icon).font(.system(size: 11, weight: .semibold)).frame(width: 24, height: 24).background(Circle().fill(on ? Color.accentColor : Color.white.opacity(0.11))); Text(title).font(.system(size: 13)); Spacer(); Text(on ? "On" : "Off").font(.caption).foregroundStyle(UITheme.secondary) } }.buttonStyle(.plain)
    }
}

private struct UnavailableFeatureRow: View {
    let icon: String
    let title: String
    var body: some View {
        HStack {
            Image(systemName: icon).font(.system(size: 11, weight: .semibold))
                .frame(width: 24, height: 24).background(Circle().fill(Color.white.opacity(0.06)))
            Text(title).font(.system(size: 13))
            Spacer()
            Text("Unavailable").font(.caption).foregroundStyle(UITheme.secondary)
        }
        .foregroundStyle(UITheme.secondary)
        .accessibilityElement(children: .combine)
    }
}

private struct MenuRow: View {
    let title: String; let badge: Bool; let action: () -> Void
    @State private var hovered = false
    var body: some View {
        Button(action: action) { HStack { Text(title).font(.system(size: 12)); if badge { Circle().fill(.orange).frame(width: 6, height: 6) }; Spacer(); Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(UITheme.secondary) }.padding(.vertical, 5).padding(.horizontal, 6).background(hovered ? Color.white.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 6)) }.buttonStyle(.plain).onHover { hovered = $0 }
    }
}

private struct ConnectionView: View {
    @ObservedObject var store: AppStore
    let canGoBack: Bool; let goBack: () -> Void
    @State private var reveal = false
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { if canGoBack { Button(action: goBack) { Image(systemName: "chevron.left") }.buttonStyle(.plain) }; Text(canGoBack ? "Settings" : "Connect LG ThinQ").font(.headline); Spacer(); if canGoBack { Button("Quit") { NSApplication.shared.terminate(nil) }.buttonStyle(.plain).foregroundStyle(UITheme.secondary) } }
            Divider()
            if !canGoBack { Text("Paste a Personal Access Token from connect-pat.lgthinq.com. It stays in this Mac’s Keychain and is sent only to LG.").font(.caption).foregroundStyle(UITheme.secondary) }
            HStack { if reveal { TextField("Personal Access Token", text: $store.token) } else { SecureField("Personal Access Token", text: $store.token) }; Button { reveal.toggle() } label: { Image(systemName: reveal ? "eye.slash" : "eye") }.buttonStyle(.plain) }.textFieldStyle(.roundedBorder)
            HStack { Text("Account country").font(.system(size: 13)); Spacer(); TextField("ZA", text: $store.country).textFieldStyle(.roundedBorder).frame(width: 55).multilineTextAlignment(.center) }
            Toggle("Remember in Keychain", isOn: $store.remember).font(.system(size: 13))
            if let error = store.error { Label(error, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange) }
            if canGoBack { Button("Refresh now") { Task { await store.refresh(); goBack() } }.buttonStyle(.bordered); Button("Sign out", role: .destructive, action: store.signOut).buttonStyle(.plain) }
            else { Button(store.busy ? "Connecting…" : "Connect") { Task { await store.connect() } }.buttonStyle(.borderedProminent).tint(.white).foregroundStyle(.black).disabled(store.busy || store.token.isEmpty).frame(maxWidth: .infinity, alignment: .trailing) }
            Text("LG Climate 0.3.2 · Native macOS menu-bar controller").font(.caption2).foregroundStyle(UITheme.secondary).frame(maxWidth: .infinity, alignment: .center).padding(.top, 4)
            Text("Not affiliated with, endorsed by, or sponsored by LG Electronics. \"LG\" and \"ThinQ\" are trademarks of their respective owners.")
                .font(.system(size: 9)).foregroundStyle(UITheme.secondary).multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }
}

private struct EmptyView: View {
    @ObservedObject var store: AppStore
    var body: some View { VStack(spacing: 12) { Image(systemName: "air.conditioner.horizontal").font(.largeTitle); Text("No air conditioners found").font(.headline); Text("Confirm that the PAT includes device permissions.").font(.caption).foregroundStyle(UITheme.secondary); Button("Sign out", action: store.signOut) }.frame(maxWidth: .infinity).padding(.vertical, 20) }
}

private func formatTemperature(_ value: Double?) -> String {
    guard let value else { return "—" }
    return value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
}

private func activity(_ unit: AirConditioner, target: Double?) -> String {
    guard unit.power else { return "Off" }
    let goal = "\(formatTemperature(target)) °C"
    return switch unit.mode { case .cool: "Cooling to \(goal)"; case .heat: "Heating to \(goal)"; case .auto: "Auto · \(goal)"; case .dry: "Dehumidifying"; case .fan: "Fan only"; case nil: "Running" }
}

private func fanTitle(_ value: String) -> String {
    switch value.uppercased() {
    case "AUTO", "NATURE": "Auto"
    case "MID": "Medium"
    case "SLOW_LOW": "Slow low"
    case "LOW_MID": "Low mid"
    case "MID_HIGH": "Mid high"
    default: value.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

private func fanSymbol(_ value: String) -> String {
    switch value.uppercased() {
    case "AUTO", "NATURE": "fan.badge.automatic"
    case "HIGH", "MID_HIGH": "fan.fill"
    default: "fan"
    }
}

private func haptic() {
    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
}
