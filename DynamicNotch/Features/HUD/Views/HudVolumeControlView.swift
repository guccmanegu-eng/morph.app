import SwiftUI
internal import AppKit
import Combine

/// Morph-native interactive controls for the system volume HUD.
/// Adapted from VolumeGlass by Aarush Prakash, with spring reveal and volume feedback.
struct HudVolumeControlView: View {
    @State private var level: Double
    @State private var isMuted: Bool
    @State private var isExpanded = false
    @State private var dismissWorkItem: DispatchWorkItem?
    @State private var volumeSubscription: AnyCancellable?
    @State private var isPulseActive = false
    @State private var lastPulseTime: TimeInterval = 0

    private let service: SystemAudioVolumeService
    private let onVolumeChanged: (Int) -> Void

    init(
        level: Int,
        service: SystemAudioVolumeService = .shared,
        onVolumeChanged: @escaping (Int) -> Void = { _ in }
    ) {
        self.service = service
        self.onVolumeChanged = onVolumeChanged
        _level = State(initialValue: Double(max(0, min(100, level))) / 100)
        _isMuted = State(initialValue: service.isMuted)
    }

    var body: some View {
        VStack(spacing: 9) {
            HStack(spacing: 10) {
                Button(action: toggleMute) {
                    Image(systemName: volumeSymbol)
                        .font(.system(size: 15, weight: .semibold))
                        .scaleEffect(isPulseActive ? 0.9 : 1)
                        .animation(.spring(response: 0.28, dampingFraction: 0.75), value: isPulseActive)
                        .foregroundColor(isMuted ? Color.gray : Color.white)
                        .frame(width: 22, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(isMuted ? "Unmute" : "Mute")
                .accessibilityLabel(isMuted ? "Unmute" : "Mute")
                .accessibilityIdentifier("hud.volume.mute")

                Slider(value: $level, in: 0...1, step: 0.01) { editing in
                    if !editing { onVolumeChanged(Int((level * 100).rounded())) }
                }
                .tint(.white)
                .accessibilityLabel("Volume")
                .accessibilityIdentifier("hud.volume.slider")

                Text("\(Int((level * 100).rounded()))%")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.88))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .frame(width: 36, alignment: .trailing)
            }

            HStack(spacing: 6) {
                ForEach([25, 50, 75, 100], id: \.self) { preset in
                    Button {
                        setPreset(preset)
                    } label: {
                        Text("\(preset)%")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(isSelected(preset) ? .white : .white.opacity(0.66))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                            .background {
                                Capsule().fill(isSelected(preset) ? Color.white.opacity(0.2) : .clear)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("hud.volume.preset.\(preset)")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background {
            RoundedRectangle(cornerRadius: 21, style: .continuous)
                .fill(Color.black.opacity(isExpanded ? 0.98 : 0.92))
                .overlay {
                    RoundedRectangle(cornerRadius: 21, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.7)
                }
                .shadow(color: .black.opacity(0.25), radius: isExpanded ? 12 : 4, y: 4)
        }
        .scaleEffect(isExpanded ? 1 : 0.96)
        .onAppear {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.72)) { isExpanded = true }
            restartAutoDismiss()
            volumeSubscription = NotificationCenter.default.publisher(for: .morphSystemVolumeDidChange)
                .compactMap { $0.userInfo?["level"] as? Int }
                .receive(on: RunLoop.main)
                .sink { changedLevel in
                    level = Double(changedLevel) / 100
                    isMuted = changedLevel == 0 && service.isMuted
                    onVolumeChanged(changedLevel)
                    restartAutoDismiss()
                }
        }
        .onDisappear {
            dismissWorkItem?.cancel()
            volumeSubscription?.cancel()
            volumeSubscription = nil
        }
        .onChange(of: level) { _, newValue in
            applyVolume(newValue)
            restartAutoDismiss()
        }
        .onChange(of: isMuted) { _, muted in
            if muted != service.isMuted {
                _ = service.toggleMute()
                level = Double(service.currentEffectiveVolume)
                isMuted = service.isMuted
                onVolumeChanged(Int((service.currentEffectiveVolume * 100).rounded()))
            }
        }
        .onChange(of: level) { oldValue, newValue in
            if newValue >= 0.999 && oldValue < 0.999 && !isMuted { pulse() }
        }
    }

    private var volumeSymbol: String {
        if isMuted || level == 0 { return "speaker.slash.fill" }
        if level > 0.66 { return "speaker.wave.3.fill" }
        if level > 0.33 { return "speaker.wave.2.fill" }
        return "speaker.wave.1.fill"
    }

    private func restartAutoDismiss() {
        dismissWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            withAnimation(.easeOut(duration: 0.12)) { isExpanded = false }
        }
        dismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: workItem)
    }

    private func applyVolume(_ value: Double) {
        let percent = service.setVolume(Float(value))
        isMuted = service.isMuted
        let next = Double(percent) / 100
        if abs(level - next) > 0.015 { level = next }
        onVolumeChanged(percent)
    }

    private func toggleMute() {
        let result = service.toggleMute()
        isMuted = service.isMuted
        level = Double(result) / 100
        onVolumeChanged(result)
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }

    private func setPreset(_ percent: Int) {
        let result = service.setVolume(Float(percent) / 100)
        isMuted = service.isMuted
        level = Double(result) / 100
        onVolumeChanged(result)
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }

    private func pulse() {
        let now = Date.timeIntervalSinceReferenceDate
        guard now - lastPulseTime >= 0.06 else { return }
        lastPulseTime = now
        withAnimation(.easeIn(duration: 0.08)) { isPulseActive = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            withAnimation(.interpolatingSpring(stiffness: 700, damping: 22)) { isPulseActive = false }
        }
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }

    private func isSelected(_ percent: Int) -> Bool {
        !isMuted && abs(Int((level * 100).rounded()) - percent) < 2
    }
}
