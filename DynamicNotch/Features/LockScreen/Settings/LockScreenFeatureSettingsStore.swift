import Foundation
import Combine

extension LockScreenWidgetAppearanceStyle: StoredSettingValue {}
extension LockScreenWidgetTintStyle: StoredSettingValue {}
extension LockScreenMediaPanelBackgroundStyle: StoredSettingValue {}
extension LockScreenClockDateFormat: StoredSettingValue {}
extension LockScreenClockFontDesign: StoredSettingValue {}
extension LockScreenMediaPresentation: StoredSettingValue {}

@MainActor
final class LockScreenFeatureSettingsStore: SettingsStoreBase {
    @StoredDefault(key: LockScreenSettings.liveActivityKey, defaultValue: true)
    var isLockScreenLiveActivityEnabled: Bool

    @StoredDefault(key: LockScreenSettings.soundKey, defaultValue: true)
    var isLockScreenSoundEnabled: Bool

    @StoredDefault(key: LockScreenSettings.customLockSoundPathKey, defaultValue: "")
    var customLockSoundPath: String

    @StoredDefault(key: LockScreenSettings.customUnlockSoundPathKey, defaultValue: "")
    var customUnlockSoundPath: String

    @StoredDefault(key: LockScreenSettings.mediaPanelKey, defaultValue: true)
    var isLockScreenMediaPanelEnabled: Bool

    @StoredDefault(key: LockScreenSettings.widgetAppearanceStyleKey, defaultValue: .ultraThinMaterial)
    var widgetAppearanceStyle: LockScreenWidgetAppearanceStyle

    @StoredDefault(key: LockScreenSettings.widgetTintStyleKey, defaultValue: .neutral)
    var widgetTintStyle: LockScreenWidgetTintStyle

    @StoredDefault(key: LockScreenSettings.liquidGlassVariantKey, defaultValue: 0)
    var liquidGlassVariant: Int

    @StoredDefault(key: LockScreenSettings.mediaPanelBackgroundStyleKey, defaultValue: .staticArtwork)
    var mediaPanelBackgroundStyle: LockScreenMediaPanelBackgroundStyle

    @StoredDefault(key: LockScreenSettings.lyricsEnabledKey, defaultValue: false)
    var isLockScreenLyricsEnabled: Bool

    @StoredDefault(key: LockScreenSettings.artworkExpandedKey, defaultValue: false)
    var isLockScreenArtworkExpanded: Bool

    @StoredDefault(key: LockScreenSettings.mediaPanelVerticalOffsetKey, defaultValue: 0.0)
    var mediaPanelVerticalOffset: Double

    @StoredDefault(key: LockScreenSettings.panelCornerRadiusKey, defaultValue: 28.0)
    var panelCornerRadius: Double

    @StoredDefault(key: LockScreenSettings.soundVolumeKey, defaultValue: 100.0)
    var soundVolume: Double

    @StoredDefault(key: LockScreenSettings.showsClockKey, defaultValue: true)
    var showsClock: Bool

    @StoredDefault(key: LockScreenSettings.showsClockDateKey, defaultValue: true)
    var showsClockDate: Bool

    @StoredDefault(key: LockScreenSettings.clockDateFormatKey, defaultValue: .abbreviated)
    var clockDateFormat: LockScreenClockDateFormat

    @StoredDefault(key: LockScreenSettings.showsClockSecondsKey, defaultValue: false)
    var showsClockSeconds: Bool

    @StoredDefault(key: LockScreenSettings.clockFontDesignKey, defaultValue: .standard)
    var clockFontDesign: LockScreenClockFontDesign

    @StoredDefault(key: LockScreenSettings.clockSizeScaleKey, defaultValue: 100.0)
    var clockSizeScale: Double

    @StoredDefault(key: LockScreenSettings.defaultMediaPresentationKey, defaultValue: .lyrics)
    var defaultMediaPresentation: LockScreenMediaPresentation

    @StoredDefault(key: LockScreenSettings.showsPresentationSwitcherKey, defaultValue: true)
    var showsPresentationSwitcher: Bool

    @StoredDefault(key: LockScreenSettings.backgroundBlurScaleKey, defaultValue: 100.0)
    var backgroundBlurScale: Double

    @StoredDefault(key: LockScreenSettings.backgroundDimmingKey, defaultValue: 0.0)
    var backgroundDimming: Double

    @StoredDefault(key: LockScreenSettings.idleBackgroundDimEnabledKey, defaultValue: true)
    var isIdleBackgroundDimEnabled: Bool

    @StoredDefault(key: LockScreenSettings.idleBackgroundDimSecondsKey, defaultValue: 10.0)
    var idleBackgroundDimSeconds: Double

    @StoredDefault(key: LockScreenSettings.keepDisplayAwakeKey, defaultValue: true)
    var isKeepDisplayAwakeEnabled: Bool

    override init(defaults: UserDefaults) {
        super.init(defaults: defaults)

        let legacyCustomSoundPath = LockScreenSettings.legacyCustomSoundPath(in: defaults) ?? ""
        let storedLockSoundPath = defaults.string(forKey: LockScreenSettings.customLockSoundPathKey)
        let storedUnlockSoundPath = defaults.string(forKey: LockScreenSettings.customUnlockSoundPathKey)

        migrateLegacyCustomSoundIfNeeded(
            legacyCustomSoundPath: legacyCustomSoundPath,
            storedLockSoundPath: storedLockSoundPath,
            storedUnlockSoundPath: storedUnlockSoundPath
        )
    }

    func reset() {
        isLockScreenLiveActivityEnabled = defaultBool(for: LockScreenSettings.liveActivityKey)
        isLockScreenSoundEnabled = defaultBool(for: LockScreenSettings.soundKey)
        customLockSoundPath = defaultString(for: LockScreenSettings.customLockSoundPathKey)
        customUnlockSoundPath = defaultString(for: LockScreenSettings.customUnlockSoundPathKey)
        isLockScreenMediaPanelEnabled = defaultBool(for: LockScreenSettings.mediaPanelKey)
        widgetAppearanceStyle = LockScreenWidgetAppearanceStyle(
            rawValue: defaultString(for: LockScreenSettings.widgetAppearanceStyleKey)
        ) ?? .ultraThinMaterial
        widgetTintStyle = LockScreenWidgetTintStyle(
            rawValue: defaultString(for: LockScreenSettings.widgetTintStyleKey)
        ) ?? .neutral
        liquidGlassVariant = defaultInt(for: LockScreenSettings.liquidGlassVariantKey)
        mediaPanelBackgroundStyle = LockScreenMediaPanelBackgroundStyle(
            rawValue: defaultString(for: LockScreenSettings.mediaPanelBackgroundStyleKey)
        ) ?? .staticArtwork
        isLockScreenLyricsEnabled = defaultBool(for: LockScreenSettings.lyricsEnabledKey)
        isLockScreenArtworkExpanded = defaultBool(for: LockScreenSettings.artworkExpandedKey)
        mediaPanelVerticalOffset = defaultDouble(for: LockScreenSettings.mediaPanelVerticalOffsetKey)
        panelCornerRadius = defaultDouble(for: LockScreenSettings.panelCornerRadiusKey)
        soundVolume = defaultDouble(for: LockScreenSettings.soundVolumeKey)
        showsClock = defaultBool(for: LockScreenSettings.showsClockKey)
        showsClockDate = defaultBool(for: LockScreenSettings.showsClockDateKey)
        clockDateFormat = LockScreenClockDateFormat(
            rawValue: defaultString(for: LockScreenSettings.clockDateFormatKey)
        ) ?? .abbreviated
        showsClockSeconds = defaultBool(for: LockScreenSettings.showsClockSecondsKey)
        clockFontDesign = LockScreenClockFontDesign(
            rawValue: defaultString(for: LockScreenSettings.clockFontDesignKey)
        ) ?? .standard
        clockSizeScale = defaultDouble(for: LockScreenSettings.clockSizeScaleKey)
        defaultMediaPresentation = LockScreenMediaPresentation(
            rawValue: defaultString(for: LockScreenSettings.defaultMediaPresentationKey)
        ) ?? .lyrics
        showsPresentationSwitcher = defaultBool(for: LockScreenSettings.showsPresentationSwitcherKey)
        backgroundBlurScale = defaultDouble(for: LockScreenSettings.backgroundBlurScaleKey)
        backgroundDimming = defaultDouble(for: LockScreenSettings.backgroundDimmingKey)
        isIdleBackgroundDimEnabled = defaultBool(for: LockScreenSettings.idleBackgroundDimEnabledKey)
        idleBackgroundDimSeconds = defaultDouble(for: LockScreenSettings.idleBackgroundDimSecondsKey)
        isKeepDisplayAwakeEnabled = defaultBool(for: LockScreenSettings.keepDisplayAwakeKey)
    }

    private func migrateLegacyCustomSoundIfNeeded(
        legacyCustomSoundPath: String,
        storedLockSoundPath: String?,
        storedUnlockSoundPath: String?
    ) {
        guard legacyCustomSoundPath.isEmpty == false else {
            return
        }

        if storedLockSoundPath == nil {
            persist(customLockSoundPath, for: LockScreenSettings.customLockSoundPathKey)
        }

        if storedUnlockSoundPath == nil {
            persist(customUnlockSoundPath, for: LockScreenSettings.customUnlockSoundPathKey)
        }

        persist("", for: LockScreenSettings.customSoundPathKey)
    }
}
