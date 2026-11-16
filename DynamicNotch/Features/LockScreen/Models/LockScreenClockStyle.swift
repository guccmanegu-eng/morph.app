//
//  LockScreenClockStyle.swift
//  DynamicNotch
//
//  User-facing styling options for the lock-screen clock.
//

import SwiftUI

enum LockScreenClockDateFormat: String, CaseIterable {
    /// "Sat Aug 29"
    case abbreviated
    /// "Saturday, August 29"
    case full
    /// "8/29/2026" — fully locale-aware numeric date
    case numeric

    var title: LocalizedStringKey {
        switch self {
        case .abbreviated:
            return "Sat Aug 29"
        case .full:
            return "Saturday, August 29"
        case .numeric:
            return "8/29/2026"
        }
    }
}

enum LockScreenClockFontDesign: String, CaseIterable {
    case standard
    case rounded
    case serif
    case monospaced

    var title: LocalizedStringKey {
        switch self {
        case .standard:
            return "Default"
        case .rounded:
            return "Rounded"
        case .serif:
            return "Serif"
        case .monospaced:
            return "Monospaced"
        }
    }

    var fontDesign: Font.Design {
        switch self {
        case .standard:
            return .default
        case .rounded:
            return .rounded
        case .serif:
            return .serif
        case .monospaced:
            return .monospaced
        }
    }
}
