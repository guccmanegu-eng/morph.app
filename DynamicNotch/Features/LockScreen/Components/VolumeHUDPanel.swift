//
//  VolumeHUDPanel.swift
//
//  Borderless, non-activating panel that parks the SwiftUI volume HUD against the
//  left edge of the screen, like the iOS 26 HUD beside the volume buttons. Click-through,
//  visible on every Space and over full-screen apps.
//

internal import AppKit
import SwiftUI

// MARK: - SwiftUI root hosted in the panel

struct VolumeHUDRoot: View {
    @ObservedObject var controller: VolumeHUDController

    private let style = VolumeHUDView.Style()

    var body: some View {
        VolumeHUDView(
            level: controller.currentVolume,
            isMuted: controller.isMuted,
            isExpanded: controller.isExpanded,
            style: style
        )
        // Slides in from the screen edge, like the iOS 26 HUD next to the buttons.
        .offset(x: controller.isVisible ? 0 : -(style.expandedWidth + VolumeHUDPanel.edgeInset))
        .opacity(controller.isVisible ? 1 : 0)
        .animation(.spring(response: 0.34, dampingFraction: 0.82), value: controller.isVisible)
        .animation(.spring(response: 0.38, dampingFraction: 0.74), value: controller.isExpanded)
        .padding(.leading, VolumeHUDPanel.edgeInset)
        .frame(
            width: VolumeHUDPanel.panelSize.width,
            height: VolumeHUDPanel.panelSize.height,
            alignment: .leading
        )
    }
}

// MARK: - Panel

@MainActor
final class VolumeHUDPanel {

    /// Gap between the screen's left edge and the pill.
    static let edgeInset: CGFloat = 10
    /// Distance from the top of the visible frame to the top of the pill.
    static let topInset: CGFloat = 90
    /// Extra room around the pill for the shadow.
    static let shadowPadding: CGFloat = 30

    static var panelSize: NSSize {
        let style = VolumeHUDView.Style()
        return NSSize(width: edgeInset + style.expandedWidth + shadowPadding,
                      height: style.height + shadowPadding * 2)
    }

    private lazy var window: NSPanel = makeWindow()
    private var hostingView: NSHostingView<VolumeHUDRoot>?
    private var orderOutTask: Task<Void, Never>?

    func attach(controller: VolumeHUDController) {
        let hosting = NSHostingView(rootView: VolumeHUDRoot(controller: controller))
        hosting.translatesAutoresizingMaskIntoConstraints = true
        hosting.frame = NSRect(
            origin: .zero,
            size: Self.panelSize
        )
        hosting.autoresizingMask = [.width, .height]
        hostingView = hosting

        window.contentView = hosting
        reposition()
    }

    func reposition() {
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let frame = screen?.visibleFrame else { return }
        let size = window.frame.size
        // Hug the left edge, top of the pill ~topInset below the menu bar.
        window.setFrameOrigin(NSPoint(
            x: frame.minX,
            y: frame.maxY - Self.topInset - size.height + Self.shadowPadding
        ))
    }

    func orderFront() {
        orderOutTask?.cancel()
        orderOutTask = nil
        reposition()
        window.alphaValue = 1
        window.orderFrontRegardless()
    }

    /// Order out only after the SwiftUI fade/collapse has had time to play.
    func orderOut() {
        orderOutTask?.cancel()
        orderOutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 260_000_000)
            guard !Task.isCancelled else { return }
            self?.window.orderOut(nil)
        }
    }

    /// Hard teardown, no animation (used at quit / stop()).
    func orderOutImmediately() {
        orderOutTask?.cancel()
        orderOutTask = nil
        window.orderOut(nil)
    }

    // MARK: - Window construction

    private func makeWindow() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false                 // the SwiftUI view draws its own
        panel.ignoresMouseEvents = true         // purely informational, never steals a click
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .statusBar                // above normal windows
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]
        panel.animationBehavior = .none         // SwiftUI animates, not AppKit
        return panel
    }
}
