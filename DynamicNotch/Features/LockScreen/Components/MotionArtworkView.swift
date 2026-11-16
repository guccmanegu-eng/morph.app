
//
//  MotionArtworkView.swift
//  DynamicNotch
//
//  Apple Music motion artwork playback and lock-screen background.
//

import SwiftUI
import AVFoundation
internal import AppKit

// MARK: - Video Surface

struct MotionArtworkVideoView: NSViewRepresentable {

    let url: URL
    var isPlaying: Bool = true

    /// Called once the layer actually has a picture to show. Views that layer
    /// this on top of a still cover use it to cross-fade in instead of
    /// flashing an empty frame.
    var onReadyForDisplay: (@MainActor () -> Void)? = nil

    func makeNSView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.onReadyForDisplay = onReadyForDisplay
        view.load(url, playing: isPlaying)
        return view
    }

    func updateNSView(_ nsView: PlayerView, context: Context) {
        nsView.onReadyForDisplay = onReadyForDisplay
        nsView.load(url, playing: isPlaying)
    }

    static func dismantleNSView(
        _ nsView: PlayerView,
        coordinator: ()
    ) {
        nsView.stop()
    }

    @MainActor
    final class PlayerView: NSView {

        private let videoLayer = AVPlayerLayer()

        private var queue: AVQueuePlayer?
        private var looper: AVPlayerLooper?
        private var currentURL: URL?

        private var statusObservation: NSKeyValueObservation?
        private var readyObservation: NSKeyValueObservation?
        private var loadGeneration = 0
        private var wantsPlayback = true

        /// Fires when the layer has a frame on screen.
        var onReadyForDisplay: (@MainActor () -> Void)?

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)

            wantsLayer = true

            videoLayer.videoGravity = .resizeAspectFill
            videoLayer.backgroundColor = NSColor.clear.cgColor

            // Motion artwork is a small ~1:1 loop stretched over a whole screen
            // (or a 500 pt cover). Ask Core Animation to interpolate smoothly
            // instead of letting it snap to nearest-neighbour blocks — that is
            // what turns an upscaled cover into "massive pixels".
            videoLayer.magnificationFilter = .linear
            videoLayer.minificationFilter = .linear

            layer?.addSublayer(videoLayer)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        // MARK: Loading

        func load(_ url: URL, playing: Bool) {
            wantsPlayback = playing

            guard currentURL != url else {
                applyPlayback()
                return
            }

            stopPlayback()

            currentURL = url
            loadGeneration += 1

            let generation = loadGeneration

            print("[Motion] Loading video: \(url.absoluteString)")

            // IMPORTANT:
            // Pass the original HLS URL to AVPlayer.
            // Do not extract individual MP4 segments from the playlist.

            let item = AVPlayerItem(url: url)

            item.preferredForwardBufferDuration = 3

            let player = AVQueuePlayer()

            player.isMuted = true
            player.volume = 0
            player.actionAtItemEnd = .advance
            player.preventsDisplaySleepDuringVideoPlayback = false

            // Let AVPlayer manage HLS buffering.
            player.automaticallyWaitsToMinimizeStalling = true

            let looper = AVPlayerLooper(
                player: player,
                templateItem: item
            )

            self.queue = player
            self.looper = looper

            videoLayer.player = player

            readyObservation?.invalidate()
            readyObservation = videoLayer.observe(
                \.isReadyForDisplay,
                options: [.initial, .new]
            ) { [weak self] _, _ in
                // Do not touch the view from the KVO thread; hop and re-check
                // the flag inside the actor instead.
                Task { @MainActor [weak self] in
                    guard let self,
                          self.loadGeneration == generation,
                          self.videoLayer.isReadyForDisplay else {
                        return
                    }
                    self.onReadyForDisplay?()
                }
            }

            statusObservation = item.observe(
                \.status,
                options: [.initial, .new]
            ) { [weak self] item, _ in

                let status = item.status

                Task { @MainActor [weak self] in
                    guard let self,
                          self.loadGeneration == generation else {
                        return
                    }

                    switch status {
                    case .readyToPlay:
                        print("[Motion] Video ready to play")
                        self.applyPlayback()

                    case .failed:
                        print(
                            "[Motion] VIDEO ERROR: " +
                            "\(item.error?.localizedDescription ?? "Unknown error")"
                        )

                    case .unknown:
                        print("[Motion] Waiting for video readiness")

                    @unknown default:
                        break
                    }
                }
            }

            applyPlayback()
        }

        // MARK: Playback

        private func applyPlayback() {
            guard let queue else { return }

            if wantsPlayback {
                queue.play()
            } else {
                queue.pause()
            }
        }

        func stop() {
            loadGeneration += 1
            currentURL = nil
            stopPlayback()
        }

        private func stopPlayback() {
            statusObservation?.invalidate()
            statusObservation = nil

            readyObservation?.invalidate()
            readyObservation = nil

            queue?.pause()

            looper?.disableLooping()
            looper = nil

            queue?.removeAllItems()
            queue = nil

            videoLayer.player = nil
        }

        // MARK: Layout

        override func layout() {
            super.layout()

            CATransaction.begin()
            CATransaction.setDisableActions(true)

            videoLayer.frame = bounds
            videoLayer.contentsScale = window?.backingScaleFactor ?? 2

            CATransaction.commit()
        }
    }
}

// MARK: - Lock Screen Background

struct MotionArtworkBackground: View {

    let videoURL: URL?

    /// Static preview displayed while the video loads.
    var previewURL: URL? = nil

    let artwork: NSImage?
    let isPlaying: Bool

    var blurRadius: CGFloat = 80
    var darkening: Double = 0.42
    var saturation: Double = 0.45
    var brightness: Double = -0.10

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    @State private var drift: CGFloat = 1.0

    var body: some View {
        ZStack {
            Color.black

            if videoURL != nil {
                videoContent
                    .blur(radius: blurRadius)
                    .saturation(saturation)
                    .brightness(brightness)
            } else {
                stillContent
            }

            LinearGradient(
                colors: [
                    .black.opacity(0.15),
                    .black.opacity(0.55)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .opacity(darkening)

            Color.black.opacity(darkening * 0.35)
        }
        .clipped()
    }

    // MARK: Layers

    private var videoContent: some View {
        ZStack {

            // Static preview stays visible underneath the video.
            if let previewURL {
                AsyncImage(url: previewURL) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .interpolation(.high)
                            .antialiased(true)
                            .aspectRatio(contentMode: .fill)
                    } else {
                        fallbackArtwork
                    }
                }
            } else {
                fallbackArtwork
            }

            // Actual animated artwork.
            if let videoURL {
                MotionArtworkVideoView(
                    url: videoURL,
                    isPlaying: isPlaying && !reduceMotion
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(videoURL)
            }
        }
    }

    /// No motion art: fill the screen with the still cover.
    ///
    /// `StillArtworkFill` tiles the cover instead of stretching one copy, so no
    /// single copy is magnified past ~1.6x its own resolution. The old code let
    /// one copy be blown up 6-7x and, with `blurRadius: 0` in the cover /
    /// motion presentations, that upscale is what read as gigantic pixels.
    @ViewBuilder
    private var stillContent: some View {
        if let artwork {
            StillArtworkFill(image: artwork, blurRadius: blurRadius)
                .saturation(saturation)
                .brightness(brightness)
                .scaleEffect(drift)
                .onAppear { startDrift() }
        } else {
            Color.black
        }
    }

    private var fallbackArtwork: some View {
        Group {
            if let artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .aspectRatio(contentMode: .fill)
            } else {
                Color.black
            }
        }
    }

    private func startDrift() {
        guard !reduceMotion, videoURL == nil else {
            return
        }

        drift = 1.08

        withAnimation(
            .easeInOut(duration: 14)
                .repeatForever(autoreverses: true)
        ) {
            drift = 1.16
        }
    }
}


// MARK: - Still cover fill

/// Fills an arbitrary rect with a still album cover without ever magnifying the
/// bitmap by a large factor.
///
/// A single copy of the artwork used to be handed a `hypot(width, height)`
/// frame — roughly 2000 pt, which is ~4000 device pixels on a Retina display.
/// A 600 px cover therefore had to be blown up 6-7x, and with `blurRadius: 0`
/// in the cover / motion presentations that upscale was plainly visible as
/// enormous square pixels.
///
/// Here the cover is instead tiled in a mirrored mosaic: every copy stays close
/// to its own resolution, mirror symmetry keeps the seams from forming visible
/// lines, and the blur finishes the job.
struct StillArtworkFill: View {

    let image: NSImage
    let blurRadius: CGFloat

    @Environment(\.displayScale) private var displayScale

    /// A single copy may be at most this much larger than the source bitmap
    /// before another tile is added.
    private static let maxUpscale: CGFloat = 1.6
    /// Grid is clamped so a tiny cover cannot explode into dozens of tiles.
    private static let maxTiles: Int = 4
    /// Mirrored neighbours must overlap slightly so the flip never leaves a seam.
    private static let tileOverlap: CGFloat = 1.04

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            // The blur samples outside the frame, so give it room to eat.
            let overscan = blurRadius * 2
            let canvas = CGSize(
                width: size.width + overscan * 2,
                height: size.height + overscan * 2
            )
            let count = Self.tileCount(for: image, filling: canvas, displayScale: displayScale)
            let tile = max(canvas.width, canvas.height) / CGFloat(count) * Self.tileOverlap

            ZStack {
                ForEach(0..<(count * count), id: \.self) { index in
                    let column = index % count
                    let row = index / count

                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .antialiased(true)
                        .frame(width: tile, height: tile)
                        .scaleEffect(
                            x: column.isMultiple(of: 2) ? 1 : -1,
                            y: row.isMultiple(of: 2) ? 1 : -1
                        )
                        .offset(
                            x: (CGFloat(column) - CGFloat(count - 1) / 2) * tile,
                            y: (CGFloat(row) - CGFloat(count - 1) / 2) * tile
                        )
                }
            }
            .frame(width: canvas.width, height: canvas.height)
            .blur(radius: blurRadius)
            .frame(width: size.width, height: size.height)
            .clipped()
        }
    }

    /// Fewest tiles whose copies all stay at or under `maxUpscale` of the source
    /// bitmap.
    private static func tileCount(
        for image: NSImage,
        filling canvas: CGSize,
        displayScale: CGFloat
    ) -> Int {
        let native = nativePixelSize(of: image)
        let shortest = max(1, min(native.width, native.height))
        let needed = max(canvas.width, canvas.height) * max(displayScale, 1)
        let raw = Int((needed / (shortest * maxUpscale)).rounded(.up))
        return min(maxTiles, max(1, raw))
    }

    private static func nativePixelSize(of image: NSImage) -> CGSize {
        let best = image.representations.max {
            ($0.pixelsWide * $0.pixelsHigh) < ($1.pixelsWide * $1.pixelsHigh)
        }
        if let best, best.pixelsWide > 0, best.pixelsHigh > 0 {
            return CGSize(width: best.pixelsWide, height: best.pixelsHigh)
        }
        return image.size
    }
}

// MARK: - Album cover with motion art

/// The large album cover in the expanded lock-screen presentation.
///
/// When Apple Music motion artwork exists the loop plays inside the cover;
/// otherwise the still artwork shows through. The still cover stays mounted
/// underneath the whole time, so there is never an empty or black frame while
/// the loop spins up, and the video only fades in once the layer has a picture.
struct MotionArtworkCover<Fallback: View>: View {

    let videoURL: URL?
    let isPlaying: Bool
    let size: CGFloat
    let cornerRadius: CGFloat

    @ViewBuilder var fallback: () -> Fallback

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var videoReady = false

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    var body: some View {
        ZStack {
            fallback()

            if let videoURL, !reduceMotion {
                MotionArtworkVideoView(
                    url: videoURL,
                    isPlaying: isPlaying,
                    onReadyForDisplay: {
                        guard !videoReady else { return }
                        withAnimation(.easeOut(duration: 0.45)) {
                            videoReady = true
                        }
                    }
                )
                .opacity(videoReady ? 1 : 0)
                .allowsHitTesting(false)
                .id(videoURL)
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .contentShape(shape)
        // A new track means a new loop: hide it again until it has a frame.
        .onChange(of: videoURL) { _, _ in
            videoReady = false
        }
        .onChange(of: reduceMotion) { _, isReduced in
            if isReduced { videoReady = false }
        }
    }
}
