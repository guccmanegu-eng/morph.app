//
//  VolumeHUDController.swift
//
//  Drives the iOS-style volume HUD: shows it on a volume change, expands the
//  capsule to reveal the bar, then collapses and fades it out.
//

import Combine
import Foundation

@MainActor
final class VolumeHUDController: ObservableObject {

    static let shared = VolumeHUDController()

    @Published var currentVolume: Double
    @Published var isVisible: Bool = false {
        didSet {
            guard oldValue != isVisible, isPanelReady else { return }
            if isVisible { panel.orderFront() } else { panel.orderOut() }
        }
    }
    /// `false` = glyph only, `true` = glyph + level bar (iOS expands on show).
    @Published var isExpanded: Bool = false

    /// How long the HUD stays on screen after the last change.
    var autoHideDelay: TimeInterval = 1.2
    /// Delay before the capsule opens after it appears.
    var expandDelay: TimeInterval = 0.11

    var isMuted: Bool { currentVolume <= 0.0001 }

    private let panel = VolumeHUDPanel()
    private var isPanelReady = false
    private var suppressor: VolumeKeySuppressor?
    private var expandTask: Task<Void, Never>?
    private var hideTask: Task<Void, Never>?

    private init() {
        self.currentVolume = SystemVolume.level
    }

    // MARK: - Lifecycle

    /// Keeps legacy call sites compiling. Key suppression itself is owned by
    /// AppDelegate/AppContainer — hand that instance over with `attach(to:)`.
    func start() {
        currentVolume = SystemVolume.level
    }

    func stop() {
        cancelTasks()
        isExpanded = false
        isVisible = false
        if isPanelReady { panel.orderOutImmediately() }
        suppressor?.onVolumeChange = nil
        suppressor = nil
    }

    /// Hook the HUD to the suppressor that AppContainer installed, so every
    /// media-key press updates the overlay.
    func attach(to suppressor: VolumeKeySuppressor) {
        self.suppressor = suppressor
        suppressor.onVolumeChange = { [weak self] newLevel in
            MainActor.assumeIsolated {
                self?.present(level: newLevel)
            }
        }
        currentVolume = SystemVolume.level
    }

    // MARK: - Presentation

    /// Show the HUD for `level` and restart the auto-hide clock.
    func present(level: Double) {
        currentVolume = min(max(level, 0), 1)
        ensurePanel()

        cancelTasks()

        if !isVisible {
            isExpanded = false
            isVisible = true

            expandTask = Task { [weak self] in
                guard let self else { return }
                let delay = UInt64(max(0, self.expandDelay) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: delay)
                guard !Task.isCancelled else { return }
                self.isExpanded = true
            }
        } else if !isExpanded {
            isExpanded = true
        }

        hideTask = Task { [weak self] in
            guard let self else { return }
            let delay = UInt64(max(0.2, self.autoHideDelay) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            self.hide()
        }
    }

    /// Legacy API — show the HUD at the current level.
    func show() {
        present(level: SystemVolume.level)
    }

    func hide() {
        cancelTasks()
        // Collapse first so the capsule shrinks back into the glyph, then fade.
        isExpanded = false
        isVisible = false
    }

    /// Nudge the level from SwiftUI (e.g. a slider) while keeping hardware in sync.
    func setVolume(_ level: Double) {
        let clamped = min(max(level, 0), 1)
        SystemVolume.set(clamped)
        present(level: clamped)
    }

    // MARK: - Internals

    private func ensurePanel() {
        guard !isPanelReady else { return }
        panel.attach(controller: self)
        isPanelReady = true
        if isVisible { panel.orderFront() }
    }

    private func cancelTasks() {
        expandTask?.cancel()
        expandTask = nil
        hideTask?.cancel()
        hideTask = nil
    }
}
