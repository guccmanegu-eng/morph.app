
//
//  AppleMusicMotionSection.swift
//  DynamicNotch
//
//  Settings section for Apple Music motion artwork.
//

import SwiftUI

struct AppleMusicMotionSection: View {

    @AppStorage("AppleMusicMotionEnabled")
    private var isEnabled = true

    @State private var status = ""
    @State private var isChecking = false

    var body: some View {

        Section {

            Toggle(
                "Show motion artwork on the lock screen",
                isOn: $isEnabled
            )

            HStack(spacing: 10) {

                Button {
                    Task {
                        await test()
                    }
                } label: {
                    Label("Test Motion Artwork", systemImage: "play.rectangle")
                }
                .disabled(isChecking)

                if isChecking {
                    ProgressView()
                        .controlSize(.small)
                }

                Spacer()

                if !status.isEmpty {
                    Text(status)
                        .font(
                            .system(
                                size: 11,
                                weight: .medium,
                                design: .monospaced
                            )
                        )
                        .foregroundStyle(status == "ok" ? .green : .secondary)
                        .lineLimit(1)
                        .textSelection(.enabled)
                }
            }

        } header: {
            Text("Apple Music Motion Artwork")

        } footer: {
            Text(
                "Apple Music provides animated artwork for selected albums. " +
                "DynamicNotch retrieves the motion video through Apple's " +
                "web-player catalogue and plays it as a muted background. " +
                "No Apple Music subscription or personal sign-in is required. " +
                "Availability depends on the album."
            )
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
    }

    @MainActor
    private func test() async {

        guard !isChecking else {
            return
        }

        isChecking = true
        status = "Checking..."

        let result = await AppleMusicMotionService.shared.verify()

        status = result
        isChecking = false

        print("[Motion] Settings test result: \(result)")
    }
}

/// Backwards compatibility with the previous Spotify settings section.

@available(*, deprecated, renamed: "AppleMusicMotionSection")
typealias SpotifyAccountSection = AppleMusicMotionSection
