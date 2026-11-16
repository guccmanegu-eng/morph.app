import SwiftUI

@MainActor
final class NotchHUDEventsHandler {
    private let notchViewModel: NotchViewModel
    private let settingsViewModel: SettingsViewModel

    init(
        notchViewModel: NotchViewModel,
        settingsViewModel: SettingsViewModel
    ) {
        self.notchViewModel = notchViewModel
        self.settingsViewModel = settingsViewModel
    }

    func handleHud(_ event: HudEvent) {
        switch event {
        case .display(let level):
            guard settingsViewModel.isHUDEnabled(.brightness) else { return }
            notchViewModel.send(
                .showTemporaryNotification(
                    HudNotchContent(
                        kind: .brightness,
                        level: level,
                        style: settingsViewModel.hudStyle,
                        indicatorStyle: settingsViewModel.hudIndicatorStyle,
                        indicatorTintStyle: settingsViewModel.hudIndicatorTintStyle,
                        showsIndicatorGlow: settingsViewModel.isHUDIndicatorGlowEnabled,
                        usesColoredLevelStroke: settingsViewModel.isHUDColoredLevelStrokeEnabled,
                        applicationSettings: settingsViewModel.application
                    ),
                    duration: settingsViewModel.temporaryActivityDuration(for: .brightness)
                )
            )

        case .keyboard(let level):
            guard settingsViewModel.isHUDEnabled(.keyboard) else { return }
            notchViewModel.send(
                .showTemporaryNotification(
                    HudNotchContent(
                        kind: .keyboard,
                        level: level,
                        style: settingsViewModel.hudStyle,
                        indicatorStyle: settingsViewModel.hudIndicatorStyle,
                        indicatorTintStyle: settingsViewModel.hudIndicatorTintStyle,
                        showsIndicatorGlow: settingsViewModel.isHUDIndicatorGlowEnabled,
                        usesColoredLevelStroke: settingsViewModel.isHUDColoredLevelStrokeEnabled,
                        applicationSettings: settingsViewModel.application
                    ),
                    duration: settingsViewModel.temporaryActivityDuration(for: .keyboard)
                )
            )

        case .volume(let level, let deviceName):
            guard settingsViewModel.isHUDEnabled(.volume) else {
                VolumeHUDOverlayController.shared.hide()
                return
            }
            if let visibleHUD = notchViewModel.notchModel.temporaryNotificationContent as? HudNotchContent,
               visibleHUD.kind == .volume {
                notchViewModel.hideTemporaryNotification()
            }
            VolumeHUDOverlayController.shared.show(
                level: level,
                deviceName: deviceName,
                duration: settingsViewModel.temporaryActivityDuration(for: .volume),
                screen: NSScreen.preferredNotchScreen(for: settingsViewModel.application)
            )
        }
    }
}
