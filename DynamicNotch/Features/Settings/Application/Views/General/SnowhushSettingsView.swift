import SwiftUI
import ServiceManagement

struct SnowhushSettingsView: View {
    @State private var refreshToken = 0
    @State private var isEnabled = Preferences.enabled
    private let controller = SnowhushController.shared

    var body: some View {
        SettingsPageScrollView {
            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Enable Snowhush", isOn: $isEnabled)
                        .onChange(of: isEnabled) { _, enabled in
                            controller.setEnabled(enabled)
                        }
                    SettingsSliderRow(
                        title: "Intensity",
                        description: "How much snow or other effects fall. Set to zero to pause falling.",
                        range: 0...100,
                        step: 1,
                        fractionLength: 0,
                        suffix: "%",
                        accessibilityIdentifier: "settings.snowhush.intensity",
                        value: binding(get: { Preferences.intensity * 100 }, set: { Preferences.intensity = $0 / 100 })
                    )
                    SettingsSliderRow(
                        title: "Falling opacity",
                        description: "Transparency of falling snow, leaves, petals, and rain.",
                        range: 10...100,
                        step: 1,
                        fractionLength: 0,
                        suffix: "%",
                        accessibilityIdentifier: "settings.snowhush.opacity",
                        value: binding(get: { Preferences.fallingOpacity * 100 }, set: { Preferences.fallingOpacity = $0 / 100 })
                    )
                    Picker("Mode", selection: binding(get: { Preferences.mode.rawValue }, set: {
                        guard let mode = Mode(rawValue: $0) else { return }
                        Preferences.mode = mode
                        Preferences.mixed = false
                    })) {
                        ForEach(Mode.allCases, id: \.rawValue) { mode in
                            Text(tr(mode.key)).tag(mode.rawValue)
                        }
                    }
                    toggle("Mixed modes", description: "Fall in both selected modes.", key: "mixed", get: { Preferences.mixed }) {
                        Preferences.mixed = $0
                    }
                    if Preferences.mixed {
                        Picker("First mode", selection: binding(get: { Preferences.mix[0].rawValue }, set: { setMixMode($0, at: 0) })) {
                            ForEach(Mode.allCases, id: \.rawValue) { mode in Text(tr(mode.key)).tag(mode.rawValue) }
                        }
                        Picker("Second mode", selection: binding(get: { Preferences.mix[1].rawValue }, set: { setMixMode($0, at: 1) })) {
                            ForEach(Mode.allCases, id: \.rawValue) { mode in Text(tr(mode.key)).tag(mode.rawValue) }
                        }
                    }
                    toggle("Halloween effects", description: "Add pumpkins and ghosts to snow.", key: "halloweenOn", get: { Preferences.halloween }) {
                        Preferences.halloween = $0
                    }
                    SettingsButtonRow(
                        title: "Clear accumulated effects",
                        description: "Blow away settled snow, leaves, and petals.",
                        buttonTitle: "Clear",
                        action: { controller.clearSnow() }
                    )
                }
            } label: {
                Text("Behavior")
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(SnowhushSettingsView.surfaceOptions, id: \.key) { option in
                        toggle(option.title, description: option.description, key: option.key, get: { Preferences.surfaces.contains(option.surface) }) { enabled in
                            var surfaces = Preferences.surfaces
                            if enabled { surfaces.insert(option.surface) } else { surfaces.remove(option.surface) }
                            Preferences.surfaces = surfaces
                        }
                    }
                    toggle("Melt settled effects", description: "Slowly melt or wither accumulated effects.", key: "meltSnow", get: { Preferences.meltSnow }) {
                        Preferences.meltSnow = $0
                    }
                    toggle("Deep interaction", description: "Let effects settle on desktop selections.", key: "deepInteraction", get: { Preferences.deepInteraction }) {
                        Preferences.deepInteraction = $0
                    }
                    toggle("Behind windows", description: "Draw the overlay behind app windows.", key: "behindWindows", get: { Preferences.behindWindows }) {
                        Preferences.behindWindows = $0
                    }
                    toggle("Show over full-screen apps", description: "Keep the overlay visible over full-screen apps.", key: "showOverFullScreen", get: { Preferences.showOverFullScreen }) {
                        Preferences.showOverFullScreen = $0
                    }
                    toggle("Show in screenshots", description: "Include the overlay in screenshots and screen sharing.", key: "showInScreenshots", get: { Preferences.showInScreenshots }) {
                        Preferences.showInScreenshots = $0
                    }
                    toggle("Maximum performance", description: "Render continuously at the display's highest refresh rate.", key: "performance", get: { Preferences.maxPerformance }) {
                        Preferences.maxPerformance = $0
                    }
                }
            } label: {
                Text("Display")
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    toggle("Open at Login", description: "Start Morph with Snowhush enabled at login.", key: "snowhush.login", get: { SMAppService.mainApp.status == .enabled }) { enabled in
                        do {
                            if enabled { try SMAppService.mainApp.register() }
                            else { try SMAppService.mainApp.unregister() }
                        } catch {
                            NSLog("Snowhush: login item change failed: \(error)")
                        }
                    }
                }
            } label: {
                Text("General")
            }
        }
        .onChange(of: refreshToken) { _, _ in
            controller.refreshSettings()
        }
    }

    private static let surfaceOptions: [(key: String, title: String, description: String, surface: Surfaces)] = [
        ("settleGround", "Ground", "Settle along the bottom edge of the screen.", .ground),
        ("settleDock", "Dock", "Settle along the Dock.", .dock),
        ("snowOnWindows", "Windows", "Settle on the tops of app windows.", .windows),
        ("settleWidgets", "Desktop widgets", "Settle on desktop widgets.", .widgets)
    ]

    private func binding<Value>(get: @escaping () -> Value, set: @escaping (Value) -> Void) -> Binding<Value> {
        Binding(
            get: { _ = refreshToken; return get() },
            set: { value in
                set(value)
                refreshToken += 1
            }
        )
    }

    private func toggle(
        _ title: String,
        description: String,
        key: String,
        get: @escaping () -> Bool,
        set: @escaping (Bool) -> Void
    ) -> some View {
        SettingsToggleRow(
            title: LocalizedStringKey(title),
            description: LocalizedStringKey(description),
            systemImage: "snowflake",
            color: .cyan,
            isOn: binding(get: get, set: set),
            accessibilityIdentifier: "settings.snowhush.\(key)"
        )
    }

    private func setMixMode(_ rawValue: Int, at index: Int) {
        guard let mode = Mode(rawValue: rawValue) else { return }
        var modes = Preferences.mix
        let otherIndex = index == 0 ? 1 : 0
        if modes[otherIndex] == mode { modes[otherIndex] = modes[index] }
        modes[index] = mode
        Preferences.mix = modes
        Preferences.mode = mode
    }
}
