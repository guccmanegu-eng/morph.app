internal import AppKit
import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

struct LockScreenSettingsView: View {
    @ObservedObject var settings: LockScreenFeatureSettingsStore
    @ObservedObject var applicationSettings: ApplicationSettingsStore
    @State private var lockSoundSelectionError: String?
    @State private var unlockSoundSelectionError: String?

    private func localized(_ key: String, fallback: String? = nil) -> String {
        applicationSettings.appLanguage.locale.dn(key, fallback: fallback)
    }
    
    var body: some View {
        SettingsPageScrollView {
            lockScreenActivity
            clockCustomization
            notchAppearance
            widgetAppearance
            artworkAppearance
            idleAppearance
        }
    }

    private var idleAppearance: some View {
        SettingsCard(title: "Idle fade") {
            SettingsToggleRow(
                title: "Fade background when idle",
                description: "Turn the artwork background black after the pointer stops moving, leaving only the clock, lyrics, album cover and player. Any mouse movement brings the background back.",
                systemImage: "moon.stars.fill",
                color: .indigo,
                iconBadge: false,
                isOn: $settings.isIdleBackgroundDimEnabled,
                accessibilityIdentifier: "settings.activities.lockScreen.idleBackgroundDim"
            )

            Divider()
                .opacity(0.6)

            SettingsSliderRow(
                title: "Idle delay",
                description: "How long the pointer has to stay still before the background fades out.",
                range: LockScreenSettings.idleBackgroundDimSecondsRange,
                step: 1,
                fractionLength: 0,
                suffix: "s",
                accessibilityIdentifier: "settings.activities.lockScreen.idleBackgroundDimDelay",
                value: $settings.idleBackgroundDimSeconds
            )
            .disabled(settings.isIdleBackgroundDimEnabled == false)
            .opacity(settings.isIdleBackgroundDimEnabled ? 1 : 0.45)

            Divider()
                .opacity(0.6)

            SettingsToggleRow(
                title: "Keep display awake",
                description: "Stop macOS from putting the screen to sleep while the lock-screen player is shown, so the screen never blanks out under the clock, lyrics and artwork.",
                systemImage: "sun.max.fill",
                color: .yellow,
                iconBadge: false,
                isOn: $settings.isKeepDisplayAwakeEnabled,
                accessibilityIdentifier: "settings.activities.lockScreen.keepDisplayAwake"
            )
        }
    }
    
    private var lockScreenActivity: some View {
        SettingsCard(title: "settings.lockScreen.card.activity") {
            SettingsToggleRow(
                title: "settings.lockScreen.activity.title",
                description: "settings.lockScreen.activity.desc",
                systemImage: "lock.fill",
                color: .black,
                stroke: true,
                isOn: $settings.isLockScreenLiveActivityEnabled,
                accessibilityIdentifier: "settings.activities.lockScreen.liveActivity"
            )
            
            Divider()
                .opacity(0.6)
                .padding(.leading, 43)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            
            SettingsToggleRow(
                title: "settings.lockScreen.mediaPanel.title",
                description: "settings.lockScreen.mediaPanel.desc",
                systemImage: "play.rectangle.fill",
                color: .pink,
                isOn: $settings.isLockScreenMediaPanelEnabled,
                accessibilityIdentifier: "settings.activities.lockScreen.mediaPanel"
            )
        }
    }
    
    private var clockCustomization: some View {
        SettingsCard(title: "Lock Screen Clock") {
            SettingsToggleRow(
                title: "Show clock",
                description: "Display the time above the album artwork on the expanded lock screen.",
                systemImage: "clock.fill",
                color: .blue,
                isOn: $settings.showsClock,
                accessibilityIdentifier: "settings.activities.lockScreen.showsClock"
            )

            Divider().opacity(0.6)

            SettingsToggleRow(
                title: "Show date",
                description: "Show the weekday and date above the time.",
                systemImage: "calendar",
                color: .indigo,
                iconBadge: false,
                isOn: $settings.showsClockDate,
                accessibilityIdentifier: "settings.activities.lockScreen.showsClockDate"
            )
            .disabled(settings.showsClock == false)
            .opacity(settings.showsClock ? 1 : 0.45)

            Divider().opacity(0.6)

            SettingsMenuRow(
                title: "Date style",
                description: "How the date above the clock is written.",
                options: Array(LockScreenClockDateFormat.allCases),
                optionTitle: { $0.title },
                accessibilityIdentifier: "settings.activities.lockScreen.clockDateFormat",
                selection: $settings.clockDateFormat
            )
            .disabled(settings.showsClock == false || settings.showsClockDate == false)
            .opacity(settings.showsClock && settings.showsClockDate ? 1 : 0.45)

            Divider().opacity(0.6)

            SettingsMenuRow(
                title: "Typeface",
                description: "Type design used for the time and the date.",
                options: Array(LockScreenClockFontDesign.allCases),
                optionTitle: { $0.title },
                accessibilityIdentifier: "settings.activities.lockScreen.clockFontDesign",
                selection: $settings.clockFontDesign
            )
            .disabled(settings.showsClock == false)
            .opacity(settings.showsClock ? 1 : 0.45)

            Divider().opacity(0.6)

            SettingsToggleRow(
                title: "Show seconds",
                description: "Add seconds to the time. Also updates the clock once per second.",
                systemImage: "timer",
                color: .orange,
                iconBadge: false,
                isOn: $settings.showsClockSeconds,
                accessibilityIdentifier: "settings.activities.lockScreen.showsClockSeconds"
            )
            .disabled(settings.showsClock == false)
            .opacity(settings.showsClock ? 1 : 0.45)

            Divider().opacity(0.6)

            SettingsSliderRow(
                title: "Clock size",
                description: "Scale the time and date relative to the lock screen.",
                range: LockScreenSettings.clockSizeScaleRange,
                step: 5,
                fractionLength: 0,
                suffix: "%",
                accessibilityIdentifier: "settings.activities.lockScreen.clockSize",
                value: $settings.clockSizeScale
            )
            .disabled(settings.showsClock == false)
            .opacity(settings.showsClock ? 1 : 0.45)

            Divider().opacity(0.6)

            clockPreview
        }
    }

    private var clockPreview: some View {
        TimelineView(.periodic(from: .now, by: settings.showsClockSeconds ? 1 : 30)) { context in
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.16, green: 0.20, blue: 0.34),
                                Color(red: 0.04, green: 0.05, blue: 0.09)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                if settings.showsClock {
                    LockScreenClockView(
                        date: context.date,
                        width: 300,
                        height: 84,
                        showsDate: settings.showsClockDate,
                        dateFormat: settings.clockDateFormat,
                        showsSeconds: settings.showsClockSeconds,
                        fontDesign: settings.clockFontDesign,
                        sizeScale: CGFloat(settings.clockSizeScale)
                    )
                } else {
                    Text("Clock hidden")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 108)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .environment(\.colorScheme, .dark)
            .allowsHitTesting(false)
        }
        .padding(.vertical, 6)
    }

    private var notchAppearance: some View {
        SettingsCard(title: "settings.lockScreen.card.notchAppearance") {
            SettingsToggleRow(
                title: "settings.lockScreen.sound.title",
                description: "settings.lockScreen.sound.desc",
                systemImage: "speaker.wave.2.fill",
                color: .red,
                isOn: $settings.isLockScreenSoundEnabled,
                accessibilityIdentifier: "settings.activities.lockScreen.sound"
            )

            Divider().opacity(0.6)

            SettingsSliderRow(
                title: "Sound volume",
                description: "Volume used for the lock and unlock sounds, including custom sounds.",
                range: LockScreenSettings.soundVolumeRange,
                step: 5,
                fractionLength: 0,
                suffix: "%",
                accessibilityIdentifier: "settings.activities.lockScreen.soundVolume",
                value: $settings.soundVolume
            )
            .disabled(settings.isLockScreenSoundEnabled == false)
            .opacity(settings.isLockScreenSoundEnabled ? 1 : 0.45)

            Divider().opacity(0.6)

            customSoundRow(for: .lock)

            Divider().opacity(0.6)

            customSoundRow(for: .unlock)
        }
    }
    
    private var artworkAppearance: some View {
        SettingsCard(title: "settings.lockScreen.card.artworkAppearance") {
            SettingsToggleRow(
                title: "settings.lockScreen.lyrics.title",
                description: "settings.lockScreen.lyrics.desc",
                systemImage: "text.quote",
                color: .purple,
                iconBadge: false,
                isOn: $settings.isLockScreenLyricsEnabled,
                accessibilityIdentifier: "settings.activities.lockScreen.lyrics"
            )

            Divider().opacity(0.6)

            SettingsMenuRow(
                title: "Default view",
                description: "What the expanded lock screen shows when it opens, until you pick a view there.",
                options: Array(LockScreenMediaPresentation.allCases),
                optionTitle: { LocalizedStringKey($0.title) },
                accessibilityIdentifier: "settings.activities.lockScreen.defaultMediaPresentation",
                selection: $settings.defaultMediaPresentation
            )

            Divider().opacity(0.6)

            SettingsToggleRow(
                title: "View switcher",
                description: "Show the Lyrics / Cover / Motion pills on the expanded lock screen. Hide them for a cleaner look.",
                systemImage: "capsule",
                color: .teal,
                iconBadge: false,
                isOn: $settings.showsPresentationSwitcher,
                accessibilityIdentifier: "settings.activities.lockScreen.showsPresentationSwitcher"
            )

            Divider().opacity(0.6)

            SettingsSliderRow(
                title: "Background blur",
                description: "How soft the artwork background is. 0% shows the sharpest image.",
                range: LockScreenSettings.backgroundBlurScaleRange,
                step: 10,
                fractionLength: 0,
                suffix: "%",
                accessibilityIdentifier: "settings.activities.lockScreen.backgroundBlur",
                value: $settings.backgroundBlurScale
            )

            Divider().opacity(0.6)

            SettingsSliderRow(
                title: "Background dimming",
                description: "Extra darkening on top of the background, for a calmer look.",
                range: LockScreenSettings.backgroundDimmingRange,
                step: 5,
                fractionLength: 0,
                suffix: "%",
                accessibilityIdentifier: "settings.activities.lockScreen.backgroundDimming",
                value: $settings.backgroundDimming
            )

            Divider().opacity(0.6)

            SettingsMenuRow(
                title: "settings.lockScreen.mediaPanelBackground.title",
                description: "settings.lockScreen.mediaPanelBackground.desc",
                options: Array(LockScreenMediaPanelBackgroundStyle.allCases),
                optionTitle: { $0.title },
                accessibilityIdentifier: "settings.general.hud.indicatorStyle",
                selection: $settings.mediaPanelBackgroundStyle
            )
            .accessibilityIdentifier("settings.activities.lockScreen.mediaPanelBackground")
        }
    }

    private var widgetAppearance: some View {
        SettingsCard(title: "settings.lockScreen.card.widgetAppearance") {
            CustomPicker(
                selection: $settings.widgetAppearanceStyle,
                options: LockScreenWidgetAppearanceStyle.availableOptions,
                title: { $0.title },
                itemHeight: 128,
                lightBackgroundImage: Image("backgroundLight"),
                darkBackgroundImage: Image("backgroundDark"),
            ) { style, isSelected in
                widgetAppearancePickerContent(for: style, isSelected: isSelected)
            }
            .accessibilityIdentifier("settings.activities.lockScreen.widgetAppearance")
            
            Divider().opacity(0.6)

            SettingsMenuRow(
                title: "Widget tint",
                description: "Color mixed into the lock-screen player panel.",
                options: Array(LockScreenWidgetTintStyle.allCases),
                optionTitle: { $0.title },
                accessibilityIdentifier: "settings.activities.lockScreen.widgetTint",
                selection: $settings.widgetTintStyle
            )

            Divider().opacity(0.6)

            SettingsSliderRow(
                title: "Corner radius",
                description: "Roundness of the lock-screen player panel.",
                range: LockScreenSettings.panelCornerRadiusRange,
                step: 2,
                fractionLength: 0,
                suffix: "pt",
                accessibilityIdentifier: "settings.activities.lockScreen.panelCornerRadius",
                value: $settings.panelCornerRadius
            )

            Divider().opacity(0.6)

            SettingsSliderRow(
                title: "settings.lockScreen.mediaPanelPosition.title",
                description: "settings.lockScreen.mediaPanelPosition.desc",
                range: LockScreenSettings.mediaPanelVerticalOffsetRange,
                step: 5,
                fractionLength: 0,
                suffix: "px",
                accessibilityIdentifier: "settings.activities.lockScreen.mediaPanelPosition",
                value: $settings.mediaPanelVerticalOffset
            )
        }
    }

    @ViewBuilder
    private func widgetAppearancePickerContent(for style: LockScreenWidgetAppearanceStyle, isSelected: Bool) -> some View {
        LockScreenWidgetAppearancePickerPreview(
            style: style,
            tintStyle: settings.widgetTintStyle,
            liquidGlassVariant: settings.liquidGlassVariant
        )
        .scaleEffect(isSelected ? 1 : 0.97)
    }

    @ViewBuilder
    private func customSoundRow(for kind: LockScreenCustomSoundKind) -> some View {
        SettingsChoiceRow(
            title: localized(kind.titleKey),
            description: localized(kind.descriptionKey),
            statusText: customSoundStatusText(for: kind),
            statusColor: customSoundStatusColor(for: kind),
            errorText: customSoundSelectionError(for: kind),
            chooseButtonTitle: hasCustomSound(for: kind) ? localized("settings.common.change") : localized("settings.common.choose"),
            onChoose: { selectCustomSound(for: kind) },
            onReset: hasCustomSound(for: kind) ? { resetCustomSoundSelection(for: kind) } : nil,
            accessibilityIdentifier: kind.accessibilityIdentifier
        )
    }

    private func customSoundStatusText(for kind: LockScreenCustomSoundKind) -> String {
        let builtInTitle = localized(kind.builtInTitleKey)

        guard let customSoundURL = customSoundURL(for: kind) else {
            return builtInTitle
        }

        guard isCustomSoundAvailable(for: kind) else {
            return String(
                format: localized("settings.lockScreen.customSound.unavailableFallback"),
                customSoundURL.lastPathComponent,
                builtInTitle.lowercased(with: applicationSettings.appLanguage.locale)
            )
        }

        return customSoundURL.lastPathComponent
    }

    private func customSoundStatusColor(for kind: LockScreenCustomSoundKind) -> Color {
        if hasCustomSound(for: kind), isCustomSoundAvailable(for: kind) == false {
            return .red
        }

        return hasCustomSound(for: kind) ? .primary : .secondary
    }

    private func hasCustomSound(for kind: LockScreenCustomSoundKind) -> Bool {
        customSoundURL(for: kind) != nil
    }

    private func isCustomSoundAvailable(for kind: LockScreenCustomSoundKind) -> Bool {
        guard let customSoundURL = customSoundURL(for: kind) else {
            return false
        }

        return FileManager.default.fileExists(atPath: customSoundURL.path)
    }

    private func customSoundURL(for kind: LockScreenCustomSoundKind) -> URL? {
        let trimmedPath = customSoundPath(for: kind).trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedPath.isEmpty == false else {
            return nil
        }

        return URL(fileURLWithPath: trimmedPath)
    }

    private func customSoundPath(for kind: LockScreenCustomSoundKind) -> String {
        switch kind {
        case .lock:
            return settings.customLockSoundPath
        case .unlock:
            return settings.customUnlockSoundPath
        }
    }

    private func setCustomSoundPath(_ path: String, for kind: LockScreenCustomSoundKind) {
        switch kind {
        case .lock:
            settings.customLockSoundPath = path
        case .unlock:
            settings.customUnlockSoundPath = path
        }
    }

    private func customSoundSelectionError(for kind: LockScreenCustomSoundKind) -> String? {
        switch kind {
        case .lock:
            return lockSoundSelectionError
        case .unlock:
            return unlockSoundSelectionError
        }
    }

    private func setCustomSoundSelectionError(_ error: String?, for kind: LockScreenCustomSoundKind) {
        switch kind {
        case .lock:
            lockSoundSelectionError = error
        case .unlock:
            unlockSoundSelectionError = error
        }
    }

    private func selectCustomSound(for kind: LockScreenCustomSoundKind) {
        let panel = NSOpenPanel()
        panel.title = localized(kind.panelTitleKey)
        panel.prompt = localized("settings.common.choose")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.audio]

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            _ = try AVAudioPlayer(contentsOf: url)
            setCustomSoundPath(url.path, for: kind)
            setCustomSoundSelectionError(nil, for: kind)
        } catch {
            setCustomSoundSelectionError(
                localized("settings.lockScreen.customSound.loadError"),
                for: kind
            )
        }
    }

    private func resetCustomSoundSelection(for kind: LockScreenCustomSoundKind) {
        setCustomSoundPath("", for: kind)
        setCustomSoundSelectionError(nil, for: kind)
    }
}

private extension LockScreenMediaPanelBackgroundStyle {
    var previewSystemImage: String {
        switch self {
        case .animatedArtwork:
            "sparkles"
        case .staticArtwork:
            "photo.fill"
        case .black:
            "circle.fill"
        }
    }
}

private struct LockScreenWidgetAppearancePickerPreview: View {
    let style: LockScreenWidgetAppearanceStyle
    let tintStyle: LockScreenWidgetTintStyle
    let liquidGlassVariant: Int

    private let panelSize = CGSize(width: 380, height: 228)
    private let panelCornerRadius: CGFloat = 34
    private let previewScale: CGFloat = 0.34
    private let progress: CGFloat = 81.0 / 214.0

    var body: some View {
        ZStack {
            LockScreenWidgetSurface(
                style: style,
                tintStyle: tintStyle,
                cornerRadius: panelCornerRadius,
                liquidGlassVariant: liquidGlassVariant
            )

            VStack {
                HStack(spacing: 18) {
                    previewArtwork

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .center, spacing: 10) {
                            Text("Midnight Echoes")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(.white.opacity(0.82))
                                .lineLimit(1)

                            Spacer(minLength: 0)

                            previewEqualizer
                        }

                        Text("Debug Ensemble")
                            .font(.system(size: 15))
                            .foregroundStyle(.white.opacity(0.5))
                            .lineLimit(1)
                    }
                }

                Spacer()

                HStack(spacing: 10) {
                    Text("1:21")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.4))

                    previewProgressBar

                    Text("3:34")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.4))
                }

                Spacer()

                ZStack {
                    HStack(spacing: 28) {
                        previewControlImage(systemName: "backward.fill", fontSize: 24, controlSize: 46, opacity: 0.9)
                        previewControlImage(systemName: "pause.fill", fontSize: 34, controlSize: 46, opacity: 0.9)
                        previewControlImage(systemName: "forward.fill", fontSize: 24, controlSize: 46, opacity: 0.9)
                    }

                    HStack {
                        previewControlImage(systemName: "star", fontSize: 22, controlSize: 46, opacity: 0.5)
                        Spacer()
                        previewControlImage(systemName: "airplayaudio", fontSize: 22, controlSize: 46, opacity: 0.5)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(22)
        }
        .frame(width: panelSize.width, height: panelSize.height)
        .clipShape(RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous))
        .shadow(color: .black.opacity(0.24), radius: 26, x: 0, y: 14)
        .scaleEffect(previewScale)
        .frame(width: scaledPanelWidth, height: scaledPanelHeight)
        .environment(\.colorScheme, .dark)
        .allowsHitTesting(false)
    }

    private var previewArtwork: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.96, green: 0.48, blue: 0.20),
                        Color(red: 1.00, green: 0.79, blue: 0.29)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 70, height: 70)
            .overlay(alignment: .bottomLeading) {
                LinearGradient(
                    colors: [
                        .black.opacity(0.28),
                        .clear
                    ],
                    startPoint: .bottom,
                    endPoint: .top
                )
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
    }

    private var previewEqualizer: some View {
        HStack(alignment: .center, spacing: 3.0) {
            ForEach([13.0, 17.0, 21.0, 16.0, 12.0], id: \.self) { barHeight in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.72),
                                .white.opacity(0.38)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 3.0, height: barHeight)
            }
        }
        .frame(height: 21, alignment: .center)
        .opacity(0.92)
    }

    private var previewProgressBar: some View {
        GeometryReader { proxy in
            let trackWidth = proxy.size.width
            let trackHeight: CGFloat = 8

            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(.white.opacity(0.15))
                    .frame(height: trackHeight)

                Capsule(style: .continuous)
                    .fill(.white.opacity(0.5))
                    .frame(width: trackWidth * progress, height: trackHeight)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .frame(height: 20)
    }

    private func previewControlImage(systemName: String, fontSize: CGFloat, controlSize: CGFloat, opacity: CGFloat) -> some View {
        Image(systemName: systemName)
            .font(.system(size: fontSize, weight: .semibold))
            .foregroundStyle(.white.opacity(opacity))
            .frame(width: controlSize, height: controlSize)
    }

    private var scaledPanelWidth: CGFloat {
        panelSize.width * previewScale
    }

    private var scaledPanelHeight: CGFloat {
        panelSize.height * previewScale
    }
}
