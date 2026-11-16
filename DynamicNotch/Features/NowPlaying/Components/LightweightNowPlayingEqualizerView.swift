//
//  LightweightNowPlayingEqualizerView.swift
//  DynamicNotch
//
//  Small decorative equalizer for the now-playing rows. Self-contained: it
//  animates on its own timeline, no shared state, no audio analysis.
//

import SwiftUI
internal import AppKit

struct LightweightNowPlayingEqualizerView: View {
    /// Every parameter has a default, and both `color:` (single) and
    /// `colors:` (per bar) are accepted, so all call sites compile.
    var isPlaying: Bool = true
    var color: NSColor = .white
    var colors: [NSColor]? = nil
    var barHeight: CGFloat = 20
    var barWidth: CGFloat = 2.2
    /// Bars to draw. `nil` uses the colour count, else 5.
    var barCount: Int? = nil
    /// Gap between bars. `nil` derives it from `barWidth`.
    var barSpacing: CGFloat? = nil

    private let tick: TimeInterval = 1.0 / 20.0

    var body: some View {
        TimelineView(.periodic(from: .now, by: tick)) { context in
            GeometryReader { proxy in
                let count = max(1, barCount ?? colors?.count ?? 5)
                let spacing = barSpacing ?? max(0.3, barWidth * 0.3)
                let maxHeight = min(barHeight, proxy.size.height)
                let time = context.date.timeIntervalSinceReferenceDate

                HStack(alignment: .bottom, spacing: spacing) {
                    ForEach(0..<count, id: \.self) { index in
                        Capsule(style: .continuous)
                            .fill(barColor(at: index))
                            .frame(
                                width: barWidth,
                                height: barHeight(
                                    at: index,
                                    time: time,
                                    maxHeight: maxHeight
                                )
                            )
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .bottomLeading)
            }
        }
    }

    private func barColor(at index: Int) -> Color {
        if let colors, !colors.isEmpty {
            return Color(nsColor: colors[index % colors.count])
        }
        return Color(nsColor: color)
    }

    private func barHeight(at index: Int, time: TimeInterval, maxHeight: CGFloat) -> CGFloat {
        guard isPlaying else {
            return max(1.5, maxHeight * 0.14)
        }

        let i = Double(index)
        // Two out-of-phase sines per bar: enough variation that it doesn't look
        // like a metronome, cheap enough to run without a timer.
        let primary = 0.5 + 0.5 * sin(time * (2.1 + i * 0.47) + i * 1.3)
        let secondary = 0.5 + 0.5 * sin(time * (3.7 + i * 0.21) + i * 2.1)
        let level = min(1, 0.22 + 0.55 * primary + 0.20 * secondary)

        return max(1.5, maxHeight * CGFloat(level))
    }
}
