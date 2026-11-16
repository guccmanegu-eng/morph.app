import Foundation

enum LockScreenSettings {
    static let liveActivityKey = "isLockScreenLiveActivityEnabled"
    static let mediaPanelKey = "isLockScreenMediaPanelEnabled"
    static let soundKey = "isLockScreenSoundEnabled"
    static let customSoundPathKey = "settings.lockScreen.customSoundPath"
    static let customLockSoundPathKey = "settings.lockScreen.customLockSoundPath"
    static let customUnlockSoundPathKey = "settings.lockScreen.customUnlockSoundPath"
    static let widgetAppearanceStyleKey = "settings.lockScreen.widgetAppearanceStyle"
    static let widgetTintStyleKey = "settings.lockScreen.widgetTintStyle"
    static let liquidGlassVariantKey = "settings.lockScreen.liquidGlassVariant"
    static let mediaPanelBackgroundStyleKey = "settings.lockScreen.mediaPanelBackgroundStyle"
    static let lyricsEnabledKey = "settings.lockScreen.lyricsEnabled"
    static let artworkExpandedKey = "settings.lockScreen.isArtworkExpanded"
    static let liquidGlassVariantRange = 0...19
    static let mediaPanelVerticalOffsetKey = "settings.lockScreen.mediaPanelVerticalOffset"
    static let mediaPanelVerticalOffsetRange = -100.0...100.0

    // MARK: Clock

    static let showsClockKey = "settings.lockScreen.showsClock"
    static let showsClockDateKey = "settings.lockScreen.showsClockDate"
    static let clockDateFormatKey = "settings.lockScreen.clockDateFormat"
    static let showsClockSecondsKey = "settings.lockScreen.showsClockSeconds"
    static let clockFontDesignKey = "settings.lockScreen.clockFontDesign"
    static let clockSizeScaleKey = "settings.lockScreen.clockSizeScale"
    static let clockSizeScaleRange = 60.0...160.0

    // MARK: Expanded artwork

    static let defaultMediaPresentationKey = "settings.lockScreen.defaultMediaPresentation"
    static let showsPresentationSwitcherKey = "settings.lockScreen.showsPresentationSwitcher"
    static let backgroundBlurScaleKey = "settings.lockScreen.backgroundBlurScale"
    static let backgroundBlurScaleRange = 0.0...250.0
    static let backgroundDimmingKey = "settings.lockScreen.backgroundDimming"
    static let backgroundDimmingRange = 0.0...80.0

    // MARK: Idle

    static let idleBackgroundDimEnabledKey = "settings.lockScreen.idleBackgroundDimEnabled"
    static let idleBackgroundDimSecondsKey = "settings.lockScreen.idleBackgroundDimSeconds"
    static let idleBackgroundDimSecondsRange = 3.0...60.0
    static let keepDisplayAwakeKey = "settings.lockScreen.keepDisplayAwake"

    // MARK: Panel

    static let panelCornerRadiusKey = "settings.lockScreen.panelCornerRadius"
    static let panelCornerRadiusRange = 14.0...40.0

    // MARK: Sound

    static let soundVolumeKey = "settings.lockScreen.soundVolume"
    static let soundVolumeRange = 0.0...100.0

    static func isLiveActivityEnabled(in defaults: UserDefaults = .standard) -> Bool {
        resolvedBoolean(forKey: liveActivityKey, defaultValue: true, in: defaults)
    }

    static func isMediaPanelEnabled(in defaults: UserDefaults = .standard) -> Bool {
        resolvedBoolean(forKey: mediaPanelKey, defaultValue: true, in: defaults)
    }

    static func isSoundEnabled(in defaults: UserDefaults = .standard) -> Bool {
        resolvedBoolean(forKey: soundKey, defaultValue: true, in: defaults)
    }

    static func legacyCustomSoundPath(in defaults: UserDefaults = .standard) -> String? {
        resolvedPath(forKey: customSoundPathKey, in: defaults)
    }

    static func customLockSoundPath(in defaults: UserDefaults = .standard) -> String? {
        resolvedPath(forKey: customLockSoundPathKey, in: defaults)
    }

    static func customUnlockSoundPath(in defaults: UserDefaults = .standard) -> String? {
        resolvedPath(forKey: customUnlockSoundPathKey, in: defaults)
    }

    static func widgetAppearanceStyle(in defaults: UserDefaults = .standard) -> LockScreenWidgetAppearanceStyle {
        guard
            let rawValue = defaults.string(forKey: widgetAppearanceStyleKey),
            let style = LockScreenWidgetAppearanceStyle(rawValue: rawValue)
        else {
            return .ultraThinMaterial
        }

        guard style.isSupportedOnCurrentSystem else {
            return .ultraThinMaterial
        }

        return style
    }

    static func widgetTintStyle(in defaults: UserDefaults = .standard) -> LockScreenWidgetTintStyle {
        guard
            let rawValue = defaults.string(forKey: widgetTintStyleKey),
            let tintStyle = LockScreenWidgetTintStyle(rawValue: rawValue)
        else {
            return .neutral
        }

        return tintStyle
    }

    static func liquidGlassVariant(in defaults: UserDefaults = .standard) -> Int {
        guard let value = defaults.object(forKey: liquidGlassVariantKey) as? Int else {
            return 8
        }

        return min(max(value, liquidGlassVariantRange.lowerBound), liquidGlassVariantRange.upperBound)
    }

    static func mediaPanelBackgroundStyle(in defaults: UserDefaults = .standard) -> LockScreenMediaPanelBackgroundStyle {
        guard
            let rawValue = defaults.string(forKey: mediaPanelBackgroundStyleKey),
            let style = LockScreenMediaPanelBackgroundStyle(rawValue: rawValue)
        else {
            return .staticArtwork
        }
        return style
    }

    static func isLyricsEnabled(in defaults: UserDefaults = .standard) -> Bool {
        resolvedBoolean(forKey: lyricsEnabledKey, defaultValue: true, in: defaults)
    }

    static func isArtworkExpanded(in defaults: UserDefaults = .standard) -> Bool {
        resolvedBoolean(forKey: artworkExpandedKey, defaultValue: false, in: defaults)
    }

    // MARK: Clock

    static func showsClock(in defaults: UserDefaults = .standard) -> Bool {
        resolvedBoolean(forKey: showsClockKey, defaultValue: true, in: defaults)
    }

    static func showsClockDate(in defaults: UserDefaults = .standard) -> Bool {
        resolvedBoolean(forKey: showsClockDateKey, defaultValue: true, in: defaults)
    }

    static func showsClockSeconds(in defaults: UserDefaults = .standard) -> Bool {
        resolvedBoolean(forKey: showsClockSecondsKey, defaultValue: false, in: defaults)
    }

    static func clockDateFormat(in defaults: UserDefaults = .standard) -> LockScreenClockDateFormat {
        guard
            let rawValue = defaults.string(forKey: clockDateFormatKey),
            let format = LockScreenClockDateFormat(rawValue: rawValue)
        else {
            return .abbreviated
        }

        return format
    }

    static func clockFontDesign(in defaults: UserDefaults = .standard) -> LockScreenClockFontDesign {
        guard
            let rawValue = defaults.string(forKey: clockFontDesignKey),
            let design = LockScreenClockFontDesign(rawValue: rawValue)
        else {
            return .standard
        }

        return design
    }

    static func clockSizeScale(in defaults: UserDefaults = .standard) -> Double {
        resolvedClampedDouble(
            forKey: clockSizeScaleKey,
            defaultValue: 100,
            range: clockSizeScaleRange,
            in: defaults
        )
    }

    // MARK: Expanded artwork

    static func defaultMediaPresentation(in defaults: UserDefaults = .standard) -> LockScreenMediaPresentation {
        guard
            let rawValue = defaults.string(forKey: defaultMediaPresentationKey),
            let presentation = LockScreenMediaPresentation(rawValue: rawValue)
        else {
            return .lyrics
        }

        return presentation
    }

    static func showsPresentationSwitcher(in defaults: UserDefaults = .standard) -> Bool {
        resolvedBoolean(forKey: showsPresentationSwitcherKey, defaultValue: true, in: defaults)
    }

    static func backgroundBlurScale(in defaults: UserDefaults = .standard) -> Double {
        resolvedClampedDouble(
            forKey: backgroundBlurScaleKey,
            defaultValue: 100,
            range: backgroundBlurScaleRange,
            in: defaults
        )
    }

    static func backgroundDimming(in defaults: UserDefaults = .standard) -> Double {
        resolvedClampedDouble(
            forKey: backgroundDimmingKey,
            defaultValue: 0,
            range: backgroundDimmingRange,
            in: defaults
        )
    }

    // MARK: Idle

    static func isIdleBackgroundDimEnabled(in defaults: UserDefaults = .standard) -> Bool {
        resolvedBoolean(forKey: idleBackgroundDimEnabledKey, defaultValue: true, in: defaults)
    }

    static func idleBackgroundDimSeconds(in defaults: UserDefaults = .standard) -> Double {
        resolvedClampedDouble(
            forKey: idleBackgroundDimSecondsKey,
            defaultValue: 10,
            range: idleBackgroundDimSecondsRange,
            in: defaults
        )
    }

    /// Keeps the display from going to sleep while the lock-screen panel is
    /// visible, so the idle fade is actually seen instead of the screen
    /// blanking out underneath it.
    static func isKeepDisplayAwakeEnabled(in defaults: UserDefaults = .standard) -> Bool {
        resolvedBoolean(forKey: keepDisplayAwakeKey, defaultValue: true, in: defaults)
    }

    // MARK: Panel

    static func panelCornerRadius(in defaults: UserDefaults = .standard) -> Double {
        resolvedClampedDouble(
            forKey: panelCornerRadiusKey,
            defaultValue: 28,
            range: panelCornerRadiusRange,
            in: defaults
        )
    }

    // MARK: Sound

    /// Stored as a percentage (0...100) so it can feed the settings slider
    /// directly; `LockScreenSoundPlayer` divides by 100 before applying it.
    static func soundVolume(in defaults: UserDefaults = .standard) -> Double {
        resolvedClampedDouble(
            forKey: soundVolumeKey,
            defaultValue: 100,
            range: soundVolumeRange,
            in: defaults
        )
    }

    static func mediaPanelVerticalOffset(in defaults: UserDefaults = .standard) -> Double {
        guard let value = defaults.object(forKey: mediaPanelVerticalOffsetKey) as? Double else {
            return 0
        }

        return min(max(value, mediaPanelVerticalOffsetRange.lowerBound), mediaPanelVerticalOffsetRange.upperBound)
    }

    private static func resolvedBoolean(
        forKey key: String,
        defaultValue: Bool,
        in defaults: UserDefaults
    ) -> Bool {
        guard defaults.object(forKey: key) != nil else {
            return defaultValue
        }

        return defaults.bool(forKey: key)
    }

    private static func resolvedClampedDouble(
        forKey key: String,
        defaultValue: Double,
        range: ClosedRange<Double>,
        in defaults: UserDefaults
    ) -> Double {
        guard let value = defaults.object(forKey: key) as? Double else {
            return defaultValue
        }

        return min(max(value, range.lowerBound), range.upperBound)
    }

    private static func resolvedPath(forKey key: String, in defaults: UserDefaults) -> String? {
        guard let rawValue = defaults.string(forKey: key) else {
            return nil
        }

        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedValue.isEmpty == false else {
            return nil
        }

        return trimmedValue
    }
}
