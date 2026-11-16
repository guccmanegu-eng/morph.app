//
//  LockScreenClockView.swift
//  DynamicNotch
//
//  macOS lock-screen clock: abbreviated date above ("Sat Aug 29"), then the
//  large, slightly glassy time. No AM/PM — the real lock screen doesn't show it.
//
//  Every visual aspect is user-configurable through LockScreenSettings:
//  visibility, date style, seconds, type design and size.
//

import SwiftUI

struct LockScreenClockView: View {
    let date: Date
    let width: CGFloat
    let height: CGFloat

    var showsDate: Bool = true
    var dateFormat: LockScreenClockDateFormat = .abbreviated
    var showsSeconds: Bool = false
    var fontDesign: LockScreenClockFontDesign = .standard
    /// Percentage, 100 = the original lock-screen size.
    var sizeScale: CGFloat = 100

    private var resolvedScale: CGFloat {
        max(0.4, sizeScale / 100)
    }

    private var timeSize: CGFloat { max(16, height * 0.66) * resolvedScale }
    private var dateSize: CGFloat { max(10, height * 0.135) * resolvedScale }

    var body: some View {
        VStack(spacing: max(0, height * 0.02)) {
            if showsDate {
                Text(dateString)
                    .font(.system(size: dateSize, weight: .semibold, design: fontDesign.fontDesign))
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }

            Text(timeString)
                .font(.system(size: timeSize, weight: .medium, design: fontDesign.fontDesign))
                .monospacedDigit()
                .tracking(-timeSize * 0.012)
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)
                .fixedSize()
        }
        .frame(width: width, height: height)
        .compositingGroup()
        .shadow(color: .black.opacity(0.20), radius: 20, x: 0, y: 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDate)
        .accessibilityAddTraits(.updatesFrequently)
    }

    // MARK: Strings

    /// 12- or 24-hour per the user's setting, but never "6:36 PM" — the lock
    /// screen shows "6:36". Seconds are only appended when asked for.
    private static let timeFormatter: DateFormatter = makeTimeFormatter(showsSeconds: false)
    private static let timeWithSecondsFormatter: DateFormatter = makeTimeFormatter(showsSeconds: true)

    private static func makeTimeFormatter(showsSeconds: Bool) -> DateFormatter {
        let locale = Locale.autoupdatingCurrent
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = .autoupdatingCurrent
        formatter.timeZone = .autoupdatingCurrent

        let template = DateFormatter.dateFormat(
            fromTemplate: showsSeconds ? "jms" : "jm",
            options: 0,
            locale: locale
        ) ?? (showsSeconds ? "h:mm:ss a" : "h:mm a")
        var format = template
        for token in [" a", "a", "'a'"] {
            format = format.replacingOccurrences(of: token, with: "")
        }
        formatter.dateFormat = format.trimmingCharacters(in: .whitespaces)

        return formatter
    }

    /// "Sat Aug 29" — abbreviated weekday and month, no comma, locale order.
    private static let abbreviatedDateFormatter: DateFormatter = makeDateFormatter(template: "EEEMMMd")

    /// "Saturday, August 29" — full weekday and month, locale order.
    private static let fullDateFormatter: DateFormatter = makeDateFormatter(template: "EEEEMMMMd")

    /// "8/29/2026" — numeric, locale order.
    private static let numericDateFormatter: DateFormatter = makeDateFormatter(template: "yMd")

    private static func makeDateFormatter(template: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.calendar = .autoupdatingCurrent
        formatter.timeZone = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter
    }

    private var timeString: String {
        let formatter = showsSeconds ? Self.timeWithSecondsFormatter : Self.timeFormatter
        return formatter.string(from: date)
    }

    private var dateString: String {
        let formatter: DateFormatter
        let stripsCommas: Bool

        switch dateFormat {
        case .abbreviated:
            formatter = Self.abbreviatedDateFormatter
            stripsCommas = true
        case .full:
            formatter = Self.fullDateFormatter
            stripsCommas = false
        case .numeric:
            formatter = Self.numericDateFormatter
            stripsCommas = false
        }

        var value = formatter.string(from: date)
        if stripsCommas {
            value = value.replacingOccurrences(of: ",", with: "")
        }

        return value.localizedCapitalizedFirstLetter
    }

    private var accessibilityDate: String {
        date.formatted(date: .complete, time: showsSeconds ? .standard : .shortened)
    }
}

private extension String {
    var localizedCapitalizedFirstLetter: String {
        guard let first else { return self }

        return String(first).localizedUppercase + dropFirst()
    }
}

// MARK: - Preview

#Preview("Clock") {
    ZStack {
        LinearGradient(colors: [.teal, .black], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()

        LockScreenClockView(date: .now, width: 640, height: 180)
    }
    .frame(width: 700, height: 240)
}
