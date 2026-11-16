//
//  SystemIdleMonitor.swift
//  DynamicNotch
//
//  Polls the system for user inactivity (mouse movement, clicks, scrolling
//  and key presses) so the lock screen can fade its artwork background to
//  black while the pointer sits still.
//
//  Uses `CGEventSource.secondsSinceLastEventType`, which needs no
//  accessibility / input-monitoring permission because it only reads a
//  timestamp, it does not observe the events themselves.
//

internal import AppKit
import Combine

@MainActor
final class SystemIdleMonitor: ObservableObject {
    /// True once the user has been inactive for at least `timeout` seconds.
    @Published private(set) var isIdle = false

    /// How long the user has to sit still before `isIdle` flips to true.
    private(set) var timeout: TimeInterval = 10

    /// When this monitor started. Idle time is capped by it so a freshly
    /// presented lock screen never opens already faded to black just because
    /// the pointer had been parked before the lock.
    private var startedAt: Date?
    private var pollTimer: Timer?

    /// Polling cadence. Fast enough that a 10 s timeout feels accurate,
    /// slow enough to be free.
    private let pollInterval: TimeInterval = 0.25

    private static let trackedEventTypes: [CGEventType] = [
        .mouseMoved,
        .leftMouseDown,
        .rightMouseDown,
        .otherMouseDown,
        .leftMouseDragged,
        .rightMouseDragged,
        .otherMouseDragged,
        .scrollWheel,
        .keyDown,
        .flagsChanged
    ]

    deinit {
        pollTimer?.invalidate()
    }

    /// Seconds since the most recent tracked input event.
    var idleSeconds: TimeInterval {
        var shortest = TimeInterval.greatestFiniteMagnitude

        for eventType in Self.trackedEventTypes {
            let seconds = CGEventSource.secondsSinceLastEventType(
                .combinedSessionState,
                eventType: eventType
            )

            guard seconds.isFinite, seconds >= 0 else { continue }
            shortest = min(shortest, seconds)
        }

        guard shortest < .greatestFiniteMagnitude, let startedAt else { return 0 }

        return min(shortest, Date().timeIntervalSince(startedAt))
    }

    func start(timeout: TimeInterval) {
        self.timeout = max(0.5, timeout)
        startedAt = Date()

        guard pollTimer == nil else {
            evaluate()
            return
        }

        let timer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.evaluate()
            }
        }

        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
        evaluate()
    }

    func updateTimeout(_ timeout: TimeInterval) {
        self.timeout = max(0.5, timeout)
        evaluate()
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        startedAt = nil
        if isIdle {
            isIdle = false
        }
    }

    private func evaluate() {
        let shouldBeIdle = idleSeconds >= timeout

        guard shouldBeIdle != isIdle else { return }
        isIdle = shouldBeIdle
    }
}
