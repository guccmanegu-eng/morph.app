//
//  VolumeHUDOverlayController.swift
//
//  iOS 26-style volume HUD: a vertical Liquid Glass pill that pops out of
//  the left edge of the screen as a thin sliver, swells into the full pill,
//  rubber-bands when you hit 0% / 100%, and tucks back into the edge.
//  Click anywhere on it to jump to that level, drag to adjust, click the
//  speaker to mute.
//

import SwiftUI
internal import AppKit
import Combine

// MARK: - Metrics

enum VolumeHUDMetrics {
    static let width: CGFloat = 54
    static let height: CGFloat = 166
    static let sliverWidth: CGFloat = 8
    static let sliverHeight: CGFloat = 118
    /// Gap between the screen edge and the pill.
    static let edgeInset: CGFloat = 10
    /// Room around the pill for its shadow, the rubber-band stretch and hover growth.
    static let padding: CGFloat = 36
    /// Height of the click target for mute at the bottom of the pill.
    static let muteZone: CGFloat = 42

    static var panelSize: CGSize {
        CGSize(width: edgeInset + width + padding * 2, height: height + padding * 2)
    }
}

// MARK: - Model

@MainActor
final class VolumeHUDModel: ObservableObject {
    enum Phase { case hidden, sliver, expanded }

    @Published var level: CGFloat = 0
    @Published var muted = false
    @Published var deviceName: String?
    @Published var phase: Phase = .hidden
    /// Rubber-band stretch: 1 = pushed past the top, -1 = pulled past the bottom.
    @Published var stretch: CGFloat = 0
    @Published var isDragging = false
    @Published var isHovering = false
    /// Bumped every time the level hits a limit (drives the glyph bounce).
    @Published var limitBump = 0
    /// `true` = pill hugs the left edge, `false` = centred in the panel.
    @Published var hugsEdge = true

    var effectiveLevel: CGFloat { muted ? 0 : level }
}

// MARK: - Controller

@MainActor
final class VolumeHUDOverlayController {
    static let shared = VolumeHUDOverlayController()

    enum Placement {
        /// Vertically centred against the left edge of the screen (where iOS puts it).
        case leftEdge
        /// Dead centre of the screen.
        case center
    }

    var placement: Placement = .leftEdge

    private let model = VolumeHUDModel()
    private let audio = SystemAudioVolumeService.shared
    private var panel: NSPanel?
    private var hideWorkItem: DispatchWorkItem?
    private var expandWorkItem: DispatchWorkItem?
    private var visibleDuration: TimeInterval = 1.6
    private var presentationToken = 0

    private init() {}

    // MARK: Public API

    func show(level: Int, deviceName: String?, duration: TimeInterval, screen: NSScreen?) {
        visibleDuration = max(1.0, duration)
        let newLevel = CGFloat(max(0, min(100, level))) / 100
        let wasShown = model.phase != .hidden

        model.deviceName = deviceName

        // While the user is dragging, the pill is the source of truth.
        if !model.isDragging {
            if wasShown, model.level == newLevel, newLevel == 1 || newLevel == 0 {
                rubberBand(up: newLevel == 1)
            }
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                model.level = newLevel
                model.muted = audio.isMuted
            }
        }

        present(on: screen)
    }

    /// Immediately tuck the HUD away (also used when the HUD gets disabled).
    func hide() {
        collapse(force: true)
    }

    // MARK: Presentation

    private func present(on screen: NSScreen?) {
        let panel = ensurePanel()
        presentationToken += 1

        if model.phase == .hidden || !panel.isVisible {
            model.hugsEdge = placement == .leftEdge
            panel.setFrame(panelFrame(on: screen), display: false)
            panel.orderFrontRegardless()

            // 1. pop out of the edge as a thin sliver …
            DispatchQueue.main.async { [weak self] in
                withAnimation(.spring(response: 0.26, dampingFraction: 0.86)) {
                    self?.model.phase = .sliver
                }
            }
            // 2. … then swell into the full pill with a little overshoot.
            let expand = DispatchWorkItem { [weak self] in
                guard let self, self.model.phase == .sliver else { return }
                withAnimation(.spring(response: 0.44, dampingFraction: 0.66)) {
                    self.model.phase = .expanded
                }
            }
            expandWorkItem?.cancel()
            expandWorkItem = expand
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.10, execute: expand)
        } else if model.phase != .expanded {
            withAnimation(.spring(response: 0.44, dampingFraction: 0.66)) {
                model.phase = .expanded
            }
        }

        scheduleHide()
    }

    private func scheduleHide(after delay: TimeInterval? = nil) {
        hideWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.collapse(force: false) }
        hideWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + (delay ?? visibleDuration), execute: item)
    }

    /// Shrink back into a sliver, slide into the edge, then order out.
    private func collapse(force: Bool) {
        hideWorkItem?.cancel()
        hideWorkItem = nil
        expandWorkItem?.cancel()
        expandWorkItem = nil
        guard let panel, panel.isVisible, model.phase != .hidden else { return }

        // Don't yank it away from under the mouse.
        if !force, model.isDragging || model.isHovering {
            scheduleHide(after: 0.6)
            return
        }

        presentationToken += 1
        let token = presentationToken

        withAnimation(.spring(response: 0.28, dampingFraction: 0.92)) {
            model.phase = .sliver
            model.isHovering = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { [weak self] in
            guard let self, self.presentationToken == token else { return }
            withAnimation(.easeIn(duration: 0.18)) { self.model.phase = .hidden }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) { [weak self] in
                guard let self, self.presentationToken == token else { return }
                self.panel?.orderOut(nil)
            }
        }
    }

    private func rubberBand(up: Bool) {
        model.limitBump += 1
        withAnimation(.easeOut(duration: 0.09)) { model.stretch = up ? 1 : -1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) { [weak self] in
            withAnimation(.spring(response: 0.42, dampingFraction: 0.48)) {
                self?.model.stretch = 0
            }
        }
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }

    // MARK: User interaction (from the pill)

    private func userSetLevel(_ value: CGFloat) {
        let clamped = max(0, min(1, value))
        audio.setVolume(Float(clamped))
        model.muted = audio.isMuted
        scheduleHide()
    }

    private func userToggleMute() {
        let result = audio.toggleMute()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
            model.muted = audio.isMuted
            model.level = CGFloat(max(0, min(100, result))) / 100
        }
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        scheduleHide()
    }

    private func userHitLimit(up: Bool) {
        model.limitBump += 1
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }

    // MARK: Window

    private func panelFrame(on screen: NSScreen?) -> NSRect {
        let visible = (screen ?? NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = VolumeHUDMetrics.panelSize
        switch placement {
        case .leftEdge:
            return NSRect(x: visible.minX,
                          y: visible.midY - size.height / 2,
                          width: size.width, height: size.height)
        case .center:
            return NSRect(x: visible.midX - size.width / 2,
                          y: visible.midY - size.height / 2,
                          width: size.width, height: size.height)
        }
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }

        let size = VolumeHUDMetrics.panelSize
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false                 // SwiftUI draws the shadow
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.ignoresMouseEvents = false        // clickable + draggable
        panel.acceptsMouseMovedEvents = true    // hover
        panel.becomesKeyOnlyIfNeeded = true
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.isExcludedFromWindowsMenu = true

        let root = VolumeHUDPillView(
            model: model,
            setLevel: { [weak self] in self?.userSetLevel($0) },
            toggleMute: { [weak self] in self?.userToggleMute() },
            hitLimit: { [weak self] in self?.userHitLimit(up: $0) },
            keepAlive: { [weak self] in self?.scheduleHide() }
        )
        let hosting = VolumeHUDHostingView(rootView: root)
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting

        self.panel = panel
        return panel
    }
}

/// Lets the very first click on the (never-key) panel start a drag.
private final class VolumeHUDHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// MARK: - Pill view

private struct VolumeHUDPillView: View {
    @ObservedObject var model: VolumeHUDModel
    let setLevel: (CGFloat) -> Void
    let toggleMute: () -> Void
    let hitLimit: (Bool) -> Void
    let keepAlive: () -> Void

    @State private var dragStartLevel: CGFloat?
    @State private var pinnedAtLimit: Bool?

    private typealias M = VolumeHUDMetrics
    private let space = "volumeHUD"

    // MARK: Geometry per phase

    private var pillWidth: CGFloat { model.phase == .expanded ? M.width : M.sliverWidth }
    private var pillHeight: CGFloat { model.phase == .expanded ? M.height : M.sliverHeight }
    private var isEngaged: Bool { model.isDragging || model.isHovering }

    /// Hidden: tucked behind the screen edge (or shrunk, when centred).
    private var hiddenOffset: CGFloat {
        guard model.phase == .hidden else { return 0 }
        return model.hugsEdge ? -(M.sliverWidth + M.edgeInset + 6) : 0
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: model.hugsEdge ? .leading : .center) {
                Color.clear
                pill(container: geo.size)
                    .padding(.leading, model.hugsEdge ? M.edgeInset : 0)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .coordinateSpace(name: space)
        }
    }

    // MARK: Pill

    private func pill(container: CGSize) -> some View {
        let shape = Capsule(style: .continuous)
        let level = model.effectiveLevel
        let s = model.stretch

        return ZStack(alignment: .bottom) {
            // White level rising from the bottom.
            Rectangle()
                .fill(Color.white)
                .frame(height: pillHeight * level)
                .frame(maxHeight: .infinity, alignment: .bottom)

            // Speaker glyph: light over the glass, grey where the fill is behind it.
            glyph(Color.white.opacity(0.66))
                .mask(alignment: .top) {
                    Rectangle().frame(height: max(0, pillHeight * (1 - level)))
                }
            glyph(Color(white: 0.56))
                .mask(alignment: .bottom) {
                    Rectangle().frame(height: max(0, pillHeight * level))
                }
        }
        .frame(width: pillWidth, height: pillHeight)
        .clipShape(shape)
        .background { glass(shape) }
        .overlay {
            // Specular rim.
            shape.strokeBorder(
                LinearGradient(colors: [.white.opacity(0.65), .white.opacity(0.10), .white.opacity(0.32)],
                               startPoint: .top, endPoint: .bottom),
                lineWidth: 0.8)
        }
        .overlay { shape.strokeBorder(Color.black.opacity(0.20), lineWidth: 0.5).padding(-0.5) }
        .shadow(color: .black.opacity(model.phase == .expanded ? 0.20 : 0.08), radius: 16, x: 0, y: 6)
        .contentShape(shape)
        // Grow a touch while hovered / dragged, like a finger on the iOS HUD.
        .scaleEffect(x: isEngaged ? 1.10 : 1, y: isEngaged ? 1.035 : 1,
                     anchor: model.hugsEdge ? .leading : .center)
        // Rubber band past 0% / 100%: stretch away from the limit, thin out a bit.
        .scaleEffect(x: 1 - 0.06 * abs(s), y: 1 + 0.08 * abs(s),
                     anchor: s >= 0 ? .bottom : .top)
        .offset(x: hiddenOffset)
        .scaleEffect(model.phase == .hidden && !model.hugsEdge ? 0.6 : 1)
        .opacity(model.phase == .hidden ? 0 : 1)
        .gesture(dragGesture(container: container))
        .onHover { hovering in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.72)) {
                model.isHovering = hovering
            }
            keepAlive()
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.72), value: model.isDragging)
        .accessibilityElement()
        .accessibilityLabel("Volume")
        .accessibilityValue("\(Int((level * 100).rounded()))%")
        .accessibilityAdjustableAction { direction in
            let step: CGFloat = direction == .increment ? 0.0625 : -0.0625
            let target = max(0, min(1, model.level + step))
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { model.level = target }
            setLevel(target)
        }
    }

    private func glyph(_ color: Color) -> some View {
        Image(systemName: symbolName, variableValue: Double(model.effectiveLevel))
            .font(.system(size: 20, weight: .medium))
            .foregroundStyle(color)
            .contentTransition(.symbolEffect(.replace))
            .symbolEffect(.bounce, value: model.limitBump)
            .frame(width: M.width, height: M.muteZone + 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .opacity(model.phase == .expanded ? 1 : 0)
            .scaleEffect(model.phase == .expanded ? 1 : 0.5)
    }

    @ViewBuilder
    private func glass(_ shape: Capsule) -> some View {
        if #available(macOS 26.0, *) {
            shape.fill(Color.white.opacity(0.05))
                .glassEffect(.clear, in: shape)
        } else {
            shape.fill(.ultraThinMaterial)
                .overlay(shape.fill(Color.white.opacity(0.08)))
        }
    }

    private var symbolName: String {
        if model.muted || model.level <= 0.0001 { return "speaker.slash.fill" }
        if let name = model.deviceName?.lowercased(),
           name.contains("airpod") || name.contains("headphone") || name.contains("headset") {
            return "headphones"
        }
        return "speaker.wave.3.fill"   // waves light up with variableValue
    }

    // MARK: Mouse

    /// Resting (unscaled) frame of the expanded pill in the container.
    private func pillRect(in container: CGSize) -> CGRect {
        let x = model.hugsEdge ? M.edgeInset : (container.width - M.width) / 2
        return CGRect(x: x, y: (container.height - M.height) / 2, width: M.width, height: M.height)
    }

    private func dragGesture(container: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(space))
            .onChanged { value in
                if dragStartLevel == nil {
                    dragStartLevel = model.effectiveLevel
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.72)) {
                        model.isDragging = true
                    }
                }
                keepAlive()

                let moved = abs(value.translation.height) + abs(value.translation.width)
                guard moved > 2, let start = dragStartLevel else { return }

                // Relative drag, like iOS: the level follows the pointer 1:1.
                let raw = start - value.translation.height / M.height
                let clamped = max(0, min(1, raw))

                // Past the ends the pill stretches instead of the level moving.
                model.stretch = max(-1, min(1, (raw - clamped) * 3.5))

                if clamped == 0 || clamped == 1 {
                    let up = clamped == 1
                    if pinnedAtLimit != up { pinnedAtLimit = up; hitLimit(up) }
                } else {
                    pinnedAtLimit = nil
                }

                if clamped != model.level || model.muted {
                    model.level = clamped
                    model.muted = false
                    setLevel(clamped)
                }
            }
            .onEnded { value in
                let moved = abs(value.translation.height) + abs(value.translation.width)
                if moved <= 2 {
                    // Click: speaker = mute, anywhere else = jump to that level.
                    let rect = pillRect(in: container)
                    if value.location.y > rect.maxY - M.muteZone {
                        toggleMute()
                    } else {
                        let target = max(0, min(1, 1 - (value.location.y - rect.minY) / rect.height))
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.78)) {
                            model.level = target
                            model.muted = false
                        }
                        setLevel(target)
                    }
                }

                dragStartLevel = nil
                pinnedAtLimit = nil
                withAnimation(.spring(response: 0.42, dampingFraction: 0.5)) {
                    model.stretch = 0
                    model.isDragging = false
                }
                keepAlive()
            }
    }
}
