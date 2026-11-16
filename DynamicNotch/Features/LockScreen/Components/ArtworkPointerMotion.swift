
//
//  ArtworkPointerMotion.swift
//  DynamicNotch
//
//  Subtle "follow the mouse" parallax for the now-playing artwork.
//
//  Observes pointer movement with both a local and a *global* NSEvent monitor,
//  so it keeps working when the notch lives in a non-activating or
//  click-through panel that never receives mouse-moved events itself.
//

import SwiftUI
internal import AppKit

// MARK: - Pointer observation

/// Reports pointer position over its own frame, normalised to −1…1 with a
/// top-left origin. Works in click-through / non-activating windows because it
/// reads `NSEvent.mouseLocation` rather than relying on delivered events.
struct ArtworkPointerObserver: NSViewRepresentable {
    let onMove: (CGPoint) -> Void
    let onExit: () -> Void

    func makeNSView(context: Context) -> ObserverView {
        let view = ObserverView()
        view.onMove = onMove
        view.onExit = onExit
        return view
    }

    func updateNSView(_ nsView: ObserverView, context: Context) {
        nsView.onMove = onMove
        nsView.onExit = onExit
    }

    final class ObserverView: NSView {
        var onMove: ((CGPoint) -> Void)?
        var onExit: (() -> Void)?

        private var trackingArea: NSTrackingArea?
        private var localMonitor: Any?
        private var globalMonitor: Any?
        private var isInside = false

        override var isFlipped: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()

            guard let window else {
                stopMonitors()
                return
            }

            window.acceptsMouseMovedEvents = true
            startMonitors()
        }

        deinit {
            stopMonitors()
        }

        // Tracking area handles the fast path when the window does get events.
        override func updateTrackingAreas() {
            super.updateTrackingAreas()

            if let trackingArea {
                removeTrackingArea(trackingArea)
            }

            let area = NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(area)
            trackingArea = area
        }

        override func mouseEntered(with event: NSEvent) { evaluate() }
        override func mouseMoved(with event: NSEvent) { evaluate() }
        override func mouseExited(with event: NSEvent) { reset() }

        /// Clicks fall through to the artwork's Button underneath.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        // MARK: Monitors

        private func startMonitors() {
            guard localMonitor == nil, globalMonitor == nil else { return }

            // Events delivered to this app (window active or not).
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
                self?.evaluate()
                return event
            }

            // Events delivered to any other app — the click-through case.
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
                self?.evaluate()
            }
        }

        private func stopMonitors() {
            if let localMonitor {
                NSEvent.removeMonitor(localMonitor)
                self.localMonitor = nil
            }
            if let globalMonitor {
                NSEvent.removeMonitor(globalMonitor)
                self.globalMonitor = nil
            }
        }

        // MARK: Maths

        private func evaluate() {
            guard let window, window.isVisible,
                  bounds.width > 0, bounds.height > 0 else { return }

            let windowPoint = window.convertPoint(fromScreen: NSEvent.mouseLocation)
            let local = convert(windowPoint, from: nil)

            if bounds.contains(local) {
                isInside = true
                onMove?(
                    CGPoint(
                        x: min(max((local.x / bounds.width) * 2 - 1, -1), 1),
                        y: min(max((local.y / bounds.height) * 2 - 1, -1), 1)
                    )
                )
            } else {
                reset()
            }
        }

        private func reset() {
            guard isInside else { return }
            isInside = false
            onExit?()
        }
    }
}

// MARK: - Modifier

struct ArtworkPointerMotion: ViewModifier {
    var maxTilt: Double = 7
    var maxOffset: CGFloat = 3.5
    var hoverScale: CGFloat = 1.03
    var perspective: CGFloat = 0.55

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var normalized: CGPoint = .zero
    @State private var isHovering = false

    private let follow = Animation.spring(response: 0.24, dampingFraction: 0.7)
    private let settle = Animation.spring(response: 0.42, dampingFraction: 0.78)

    func body(content: Content) -> some View {
        content
            .scaleEffect(isHovering ? hoverScale : 1, anchor: .center)
            .offset(x: normalized.x * maxOffset, y: normalized.y * maxOffset)
            .rotation3DEffect(
                .degrees(-Double(normalized.y) * maxTilt),
                axis: (x: 1, y: 0, z: 0),
                perspective: perspective
            )
            .rotation3DEffect(
                .degrees(Double(normalized.x) * maxTilt),
                axis: (x: 0, y: 1, z: 0),
                perspective: perspective
            )
            .animation(follow, value: normalized)
            .animation(settle, value: isHovering)
            .background {
                if !reduceMotion {
                    ArtworkPointerObserver(
                        onMove: { point in
                            isHovering = true
                            normalized = point
                        },
                        onExit: {
                            isHovering = false
                            normalized = .zero
                        }
                    )
                }
            }
    }
}

extension View {
    /// Gentle pointer-driven tilt/drift. Apply to the button that wraps the
    /// artwork — never to the artwork and the button both.
    func artworkPointerMotion(
        maxTilt: Double = 7,
        maxOffset: CGFloat = 3.5,
        hoverScale: CGFloat = 1.03,
        perspective: CGFloat = 0.55
    ) -> some View {
        modifier(
            ArtworkPointerMotion(
                maxTilt: maxTilt,
                maxOffset: maxOffset,
                hoverScale: hoverScale,
                perspective: perspective
            )
        )
    }
}

// MARK: - Preview

#Preview("Artwork motion") {
    ZStack {
        Color.black.ignoresSafeArea()

        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [.pink, .purple, .indigo],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 60, height: 60)
            .artworkPointerMotion()
    }
    .frame(width: 220, height: 220)
}
