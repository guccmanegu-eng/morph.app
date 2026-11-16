import SwiftUI

enum NotchBackgroundStyle: String, CaseIterable {
    case black
    case gradient

    static var availableOptions: [Self] {
        return Array(allCases)
    }

    var title: LocalizedStringKey {
        switch self {
        case .black:
            return "settings.notch.backgroundStyle.black"
        case .gradient:
            return "settings.notch.backgroundStyle.gradient"
        }
    }

    var symbolName: String {
        switch self {
        case .black:
            return "circle.fill"
        case .gradient:
            return "circle.lefthalf.filled"
        }
    }

    var isSupportedOnCurrentSystem: Bool {
        return true
    }

    static func resolved(_ rawValue: String?) -> NotchBackgroundStyle {
        guard let rawValue,
              let style = NotchBackgroundStyle(rawValue: rawValue) else {
            return .black
        }

        return style
    }

    @ViewBuilder
    var background: some View {
        switch self {
        case .black:
            Color.black

        case .gradient:
            LinearGradient(
                colors: [
                    Color.black,
                    Color.black.opacity(0.75),
                    Color.black.opacity(0.4),
                    Color.black.opacity(0.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}
