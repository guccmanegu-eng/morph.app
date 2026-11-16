//
//  DisplaySleepPreventer.swift
//  DynamicNotch
//
//  Holds a `PreventUserIdleDisplaySleep` power assertion so macOS does not
//  blank the display while the lock-screen media panel is on screen. Without
//  it the system's own idle timer wins: the screen turns off mid-fade and the
//  fade-to-black state is never actually seen.
//
//  No entitlement is required for this assertion type; it is released as soon
//  as the panel goes away (or the app quits).
//

internal import IOKit.pwr_mgt
import Foundation

@MainActor
final class DisplaySleepPreventer {
    static let shared = DisplaySleepPreventer()

    private var assertionID: IOPMAssertionID?

    private init() {}

    var isPreventingDisplaySleep: Bool { assertionID != nil }

    /// Idempotent: calling it while the assertion is already held is a no-op.
    func preventDisplaySleep(reason: String) {
        guard assertionID == nil else { return }

        var newAssertionID: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &newAssertionID
        )

        guard result == kIOReturnSuccess else { return }

        assertionID = newAssertionID
    }

    func allowDisplaySleep() {
        guard let assertionID else { return }

        IOPMAssertionRelease(assertionID)
        self.assertionID = nil
    }
}
