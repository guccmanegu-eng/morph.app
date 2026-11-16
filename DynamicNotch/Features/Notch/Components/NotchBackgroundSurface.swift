import SwiftUI

/// Background fill for the notch / Dynamic Island.
///
/// `.gradient` is a *liquid glass* ramp: opaque black at the top (so the
/// surface merges with the notch / bezel), dissolving downward into clear
/// glass that lets the wallpaper through with a frosted, refracted edge.
struct NotchBackgroundSurface: View {

    let style: NotchBackgroundStyle

    let topCornerRadius: CGFloat
    let bottomCornerRadius: CGFloat

    let isDynamicIsland: Bool
    let dynamicIslandCornerRadius: CGFloat

    let strokeColor: Color
    var strokeWidth: CGFloat = 2.0

    var height: CGFloat? = nil
    var baseWidth: CGFloat? = nil
    var baseHeight: CGFloat? = nil

    /// How far down the solid black holds before it starts dissolving.
    var blackHold: CGFloat = 0.42
    /// Strength of the specular rim that sells the glass edge.
    var glassRimOpacity: Double = 0.28

    var body: some View {
        if isDynamicIsland {
            let shape = DynamicIslandShape(
                cornerRadius: dynamicIslandCornerRadius
            )

            baseSurface(shape: shape)
                .contentShape(shape)
                .overlay {
                    shape.stroke(strokeColor, lineWidth: strokeWidth)
                }
        } else {
            let shape = NotchShape(
                topCornerRadius: topCornerRadius,
                bottomCornerRadius: bottomCornerRadius
            )

            baseSurface(shape: shape)
                .contentShape(shape)
                .overlay {
                    shape.stroke(strokeColor, lineWidth: strokeWidth)
                }
        }
    }

    @ViewBuilder
    private func baseSurface<S: Shape>(shape: S) -> some View {
        switch style {
        case .black:
            shape.fill(.black)

        case .gradient:
            liquidGlass(shape: shape)
        }
    }

    // MARK: - Liquid glass ramp

    /// Layer order matters:
    /// 1. frosted body, masked so the glass strengthens toward the bottom
    /// 2. faint white sheen so the glass still reads over a dark wallpaper
    /// 3. the black cap, which is what fades away
    /// 4. an inner specular rim on top of the outer stroke
    private func liquidGlass<S: Shape>(shape: S) -> some View {
        ZStack {
            shape
                .fill(.ultraThinMaterial)
                .mask {
                    shape.fill(
                        LinearGradient(
                            stops: glassRamp,
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }

            shape.fill(
                LinearGradient(
                    stops: [
                        .init(color: .white.opacity(0.00), location: 0.00),
                        .init(color: .white.opacity(0.02), location: 0.55),
                        .init(color: .white.opacity(0.08), location: 1.00)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            shape.fill(
                LinearGradient(
                    stops: blackRamp,
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            if glassRimOpacity > 0 {
                shape.stroke(
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(glassRimOpacity), location: 0.00),
                            .init(color: .white.opacity(glassRimOpacity * 0.28), location: 0.45),
                            .init(color: .white.opacity(glassRimOpacity * 0.85), location: 1.00)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
                .blendMode(.plusLighter)
            }
        }
    }

    private var blackRamp: [Gradient.Stop] {
        [
            .init(color: .black, location: 0.0),
            .init(color: .black, location: blackHold),
            .init(color: .black.opacity(0.88), location: blackHold + 0.16),
            .init(color: .black.opacity(0.58), location: blackHold + 0.30),
            .init(color: .black.opacity(0.24), location: blackHold + 0.42),
            .init(color: .clear, location: 1.0)
        ]
    }

    private var glassRamp: [Gradient.Stop] {
        [
            .init(color: .white.opacity(0.0), location: 0.0),
            .init(color: .white.opacity(0.45), location: 0.55),
            .init(color: .white.opacity(1.0), location: 1.0)
        ]
    }
}
