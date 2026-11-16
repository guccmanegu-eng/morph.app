//
//  VolumeKeySuppressor.swift
//  DynamicNotch
//
//  Swallows the system volume HUD by intercepting the media keys in a
//  CGEvent tap, applies the volume through CoreAudio and hands the new level
//  to the overlay.
//
//  Must be a member of the DynamicNotch app target — both
//  VolumeHUDController and AppContainer reference VolumeKeySuppressor and
//  SystemVolume from this file.
//

internal import AppKit
import AudioToolbox
import CoreAudio
import CoreGraphics

@MainActor
final class VolumeKeySuppressor {

    var onVolumeChange: ((Double) -> Void)?

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isInstalled = false

    private static let volumeUp: Int64 = 0
    private static let volumeDown: Int64 = 1
    private static let mute: Int64 = 7

    func install() {
        guard !isInstalled else { return }

        let mask = (1 << 14) // 14 is the systemDefined event type raw value

        let callback: CGEventTapCallBack = { _, _, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let suppressor = Unmanaged<VolumeKeySuppressor>
                .fromOpaque(refcon)
                .takeUnretainedValue()
            let handled = MainActor.assumeIsolated { suppressor.handle(event) }
            return handled ? nil : Unmanaged.passUnretained(event)
        }

        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,          // must be active to swallow the HUD
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            NSLog("[DynamicNotch] volume tap failed")
            return
        }

        tap = port
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        isInstalled = true
    }

    func uninstall() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            }
            CFMachPortInvalidate(tap)
        }
        tap = nil
        runLoopSource = nil
        isInstalled = false
    }

    private func handle(_ event: CGEvent) -> Bool {
        guard event.type.rawValue == 14,
              let nsEvent = NSEvent(cgEvent: event),
              nsEvent.subtype.rawValue == 8 else { return false }

        let keyCode = (nsEvent.data1 & 0xFFFF0000) >> 16
        let isDown = ((nsEvent.data1 & 0x0000FF00) >> 8) == 0x0A
        guard isDown else { return true }   // swallow the key-up too

        let current = SystemVolume.level
        var newValue = current

        switch Int64(keyCode) {
        case Self.volumeUp:   newValue = min(1, current + 1.0 / 16.0)
        case Self.volumeDown: newValue = max(0, current - 1.0 / 16.0)
        case Self.mute:       newValue = current > 0 ? 0 : (SystemVolume.lastNonZero ?? 0.5)
        default:              return false
        }

        SystemVolume.set(newValue)
        onVolumeChange?(newValue)
        return true
    }
}

/// Thin CoreAudio wrapper for the default output device's volume.
enum SystemVolume {

    static nonisolated(unsafe) var lastNonZero: Double?

    static var level: Double {
        guard let device = defaultOutputDevice() else { return 0 }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectHasProperty(device, &address),
              AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else {
            return 0
        }
        return Double(value)
    }

    static func set(_ level: Double) {
        guard let device = defaultOutputDevice() else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        let clampedValue = min(max(level, 0), 1)
        var value = Float32(clampedValue)
        if value > 0 { lastNonZero = Double(value) }
        AudioObjectSetPropertyData(
            device, &address, 0, nil,
            UInt32(MemoryLayout<Float32>.size), &value
        )
    }

    private static func defaultOutputDevice() -> AudioObjectID? {
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(
            AudioObjectSystem(), &address, 0, nil, &size, &device
        ) == noErr else { return nil }
        return device
    }

    private static func AudioObjectSystem() -> AudioObjectID {
        AudioObjectID(kAudioObjectSystemObject)
    }
}
