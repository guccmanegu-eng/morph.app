//
//  VolumeHUDView.swift
//
//  iOS 26-style volume HUD: a tall Liquid Glass pill hugging the left edge
//  of the screen (next to where the iPhone's volume buttons are). The level
//  fills up from the bottom in solid white, the speaker glyph sits near the
//  bottom and flips colour where the fill passes behind it. The pill slides
//  out of the edge as a thin sliver and swells to full width.
//

import SwiftUI

struct VolumeHUDView: View {

    // MARK: - Style

    struct Style {
        /// Width of the sliver peeking out from the screen edge.
        var collapsedWidth: CGFloat = 12
        /// Width of the full pill.
        var expandedWidth: CGFloat = 50
        /// Height of the sliver.
        var collapsedHeight: CGFloat = 124
        /// Height of the full pill.
        var height: CGFloat = 164
        var iconSize: CGFloat = 17
        /// Distance from the bottom of the pill to the glyph's centre.
        var iconBottomOffset: CGFloat = 30
        /// Fill colour of the level.
        var fill: Color = .white
        /// Glyph colour over the glass.
        var iconOnGlass: Color = .white.opacity(0.72)
        /// Glyph colour over the white fill.
        var iconOnFill: Color = Color(white: 0.55)

        init() {}
    }

    // MARK: - Inputs

    var level: Double          // 0...1
    var isMuted: Bool
    var isExpanded: Bool       // false = edge sliver, true = full pill
    var style: Style

    init(
        level: Double,
        isMuted: Bool = false,
        isExpanded: Bool = true,
        style: Style = Style()
    ) {
        self.level = min(max(level, 0), 1)
        self.isMuted = isMuted
        self.isExpanded = isExpanded
        self.style = style
    }

    private var width: CGFloat { isExpanded ? style.expandedWidth : style.collapsedWidth }
    private var height: CGFloat { isExpanded ? style.height : style.collapsedHeight }
    private var shownLevel: Double { isMuted ? 0 : level }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottom) {
            // Level fill rising from the bottom, clipped by the pill.
            levelFill

            // Glyph: two copies, each masked to the part it sits over.
            glyph(color: style.iconOnGlass)
                .mask(alignment: .top) {
                    Rectangle().frame(height: max(0, height * (1 - shownLevel)))
                }
            glyph(color: style.iconOnFill)
                .mask(alignment: .bottom) {
                    Rectangle().frame(height: max(0, height * shownLevel))
                }
        }
        .frame(width: width, height: height)
        .clipShape(Capsule(style: .continuous))
        .background { glass }
        .overlay { rim }
        .shadow(color: .black.opacity(0.22), radius: 18, x: 0, y: 8)
        .animation(.spring(response: 0.38, dampingFraction: 0.74), value: isExpanded)
        .animation(.spring(response: 0.28, dampingFraction: 0.90), value: level)
        .animation(.easeInOut(duration: 0.15), value: isMuted)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Volume")
        .accessibilityValue("\(Int((level * 100).rounded())) percent")
    }

    // MARK: - Pieces

    private var levelFill: some View {
        Rectangle()
            .fill(style.fill)
            .overlay(alignment: .top) {
                // Soft sheen on the top edge of the fill, like the glass meniscus.
                LinearGradient(colors: [.white, .white.opacity(0)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 6)
                    .opacity(0.6)
            }
            .frame(height: height * shownLevel)
            .frame(maxHeight: .infinity, alignment: .bottom)
    }

    private func glyph(color: Color) -> some View {
        Image(systemName: symbolName)
            .font(.system(size: style.iconSize, weight: .semibold))
            .foregroundStyle(color)
            .contentTransition(.symbolEffect(.replace))
            .frame(width: style.expandedWidth, height: style.iconBottomOffset * 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .opacity(isExpanded ? 1 : 0)
            .scaleEffect(isExpanded ? 1 : 0.6)
    }

    @ViewBuilder
    private var glass: some View {
        if #available(macOS 26.0, *) {
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.06))
                .glassEffect(.clear, in: Capsule(style: .continuous))
        } else {
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(Capsule(style: .continuous).fill(Color.white.opacity(0.08)))
        }
    }

    /// Thin bright rim + inner highlight that sells the glass edge.
    private var rim: some View {
        ZStack {
            Capsule(style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.55), .white.opacity(0.12), .white.opacity(0.35)],
                        startPoint: .top, endPoint: .bottom
                    ),
                    lineWidth: 0.8
                )
            Capsule(style: .continuous)
                .strokeBorder(Color.black.opacity(0.18), lineWidth: 0.5)
                .padding(-0.5)
        }
        .allowsHitTesting(false)
    }

    private var symbolName: String {
        if isMuted || level <= 0.0001 { return "speaker.slash.fill" }
        switch level {
        case ..<0.34: return "speaker.wave.1.fill"
        case ..<0.67: return "speaker.wave.2.fill"
        default:      return "speaker.wave.3.fill"
        }
    }
}

// MARK: - Preview

#if DEBUG
struct VolumeHUDView_Previews: PreviewProvider {
    static var previews: some View {
        HStack(alignment: .top, spacing: 24) {
            VolumeHUDView(level: 0.08, isExpanded: true)
            VolumeHUDView(level: 0.62, isExpanded: true)
            VolumeHUDView(level: 0.0, isMuted: true, isExpanded: true)
            VolumeHUDView(level: 0.3, isExpanded: false)
        }
        .padding(40)
        .frame(width: 420, height: 280)
        .background(
            LinearGradient(colors: [.gray, .brown.opacity(0.6)], startPoint: .top, endPoint: .bottom)
        )
    }
}
#endif
