//
//  LockScreenNowPlaying.swift
//  DynamicNotch
//
//  The whole lock-screen now-playing stack in one file:
//   - LockScreenNowPlayingView          (panel row)
//   - LockScreenNowPlayingPanelView     (full-screen expanded presentation)
//  LightweightNowPlayingEqualizerView comes from
//  Features/NowPlaying/Components (not redeclared here).
//
//  Pointer parallax lives in ArtworkPointerMotion.swift.
//

import SwiftUI
internal import AppKit
import Combine

struct LockScreenNowPlayingView: View {
    @Environment(\.notchScale) var scale
    @ObservedObject var nowPlayingViewModel: NowPlayingViewModel
    @ObservedObject var mediaSettings: MediaAndFilesSettingsStore
    @Binding var onTapArtwork: Bool
    
    @State private var scrubProgress: CGFloat?
    
    private var resolvedSnapshot: NowPlayingSnapshot {
        nowPlayingViewModel.snapshot ?? NowPlayingSnapshot(
            title: "Nothing Playing",
            artist: "Start playback to see live metadata",
            album: "Debug Preview",
            duration: 0,
            elapsedTime: 0,
            playbackRate: 0,
            artworkData: nil,
            refreshedAt: .now
        )
    }
    
    var body: some View {
        let snapshot = resolvedSnapshot
        
        return TimelineView(.periodic(from: .now, by: progressTick(for: snapshot))) { context in
            timelineContent(snapshot: snapshot, at: context.date)
        }
    }
    
    private func timelineContent(snapshot: NowPlayingSnapshot, at date: Date) -> some View {
        let elapsedTime = nowPlayingViewModel.snapshot != nil ?
        nowPlayingViewModel.elapsedTime(at: date) :
        snapshot.elapsedTime
        let progress = progressValue(elapsedTime: elapsedTime, duration: snapshot.duration)
        let displayedProgress = min(max(scrubProgress ?? progress, 0), 1)
        let displayedElapsedTime = snapshot.duration > 0 ?
        TimeInterval(displayedProgress) * snapshot.duration :
        elapsedTime
        let appearance = mediaSettings.nowPlayingAppearanceOptions
        
        return VStack {
            HStack(spacing: 15) {
                if onTapArtwork == false {
                    Button(action: {withAnimation(.spring(response: 0.6)) { onTapArtwork = true }}) {
                        ArtworkView(
                            nowPlayingViewModel: nowPlayingViewModel,
                            width: 60,
                            height: 60,
                            cornerRadius: 10,
                            usesFlipAnimation: false
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PlaybackSourceButtonStyle())
                }
                
                HStack(alignment: .top) {
                    Button(action: {withAnimation(.spring(response: 0.6)) { onTapArtwork.toggle() }}) {
                        VStack(alignment: .leading, spacing: 2) {
                            MarqueeText(
                                .constant(displayTitle(for: snapshot)),
                                font: .system(size: 16, weight: .medium),
                                nsFont: .headline,
                                textColor: .white.opacity(0.8),
                                backgroundColor: .clear,
                                minDuration: 2.0,
                                frameWidth: onTapArtwork ? 260.scaled(by: scale) : 180.scaled(by: scale)
                            )

                            MarqueeText(
                                .constant(displayArtist(for: snapshot)),
                                font: .system(size: 14),
                                nsFont: .headline,
                                textColor: .white.opacity(0.5),
                                backgroundColor: .clear,
                                minDuration: 3.0,
                                frameWidth: onTapArtwork ? 260.scaled(by: scale) : 180.scaled(by: scale)
                            )
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PlaybackSourceButtonStyle())

                    Spacer()
                    
                    LightweightNowPlayingEqualizerView(
                        isPlaying: snapshot.isPlaying,
                        colors: [NSColor.white.withAlphaComponent(0.7)],
                        barHeight: 20,
                        barWidth: 2.2
                    )
                    .frame(width: 13, height: 15)
                }
                .padding(.trailing, 5)
            }
            Spacer()
            
            PlayerProgressBar(
                progress: displayedProgress,
                displayedElapsedTime: displayedElapsedTime,
                duration: snapshot.duration,
                isInteractive: snapshot.duration > 0,
                tintGradient: {
                    switch appearance.progressTintStyle {
                    case .default:
                        return nil
                    case .artwork:
                        return nowPlayingViewModel.artworkPalette.equalizerGradient
                    case .systemAccent:
                        return LinearGradient(
                            colors: [.accentColor, .accentColor.opacity(0.7)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    }
                }(),
                primaryColor: progressTimeColor(isPrimary: true, appearance: appearance),
                secondaryColor: progressTimeColor(isPrimary: false, appearance: appearance),
                onScrubChanged: { newProgress in
                    scrubProgress = newProgress
                },
                onScrubEnded: { newProgress in
                    nowPlayingViewModel.seek(to: snapshot.duration * TimeInterval(newProgress))
                    scrubProgress = nil
                }
            )
            
            Spacer()
            
            ZStack {
                HStack(spacing: 25) {
                    PlayerControlButton(
                        systemImage: "backward.fill",
                        fontSize: 22,
                        width: 42,
                        height: 42
                    ) {
                        nowPlayingViewModel.previousTrack()
                    }
                    
                    PlayerControlButton(
                        systemImage: snapshot.isPlaying ? "pause.fill" : "play.fill",
                        fontSize: 32,
                        width: 42,
                        height: 42
                    ) {
                        nowPlayingViewModel.togglePlayPause()
                    }
                    
                    PlayerControlButton(
                        systemImage: "forward.fill",
                        fontSize: 22,
                        width: 42,
                        height: 42
                    ) {
                        nowPlayingViewModel.nextTrack()
                    }
                }
                
                HStack {
                    if appearance.showsFavoriteButton {
                        FavoriteTrackButton(
                            nowPlayingViewModel: nowPlayingViewModel,
                            width: 42,
                            height: 42,
                            fontSize: 21
                        )
                    }
                    
                    Spacer()
                    
                    if appearance.showsOutputDeviceButton {
                        AudioOutputRoutePickerButton(
                            nowPlayingViewModel: nowPlayingViewModel,
                            width: 42,
                            height: 42,
                            fontSize: 21
                        )
                    }
                }
                .padding(.horizontal, 5)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(18)
    }
    
    private func displayTitle(for snapshot: NowPlayingSnapshot) -> String {
        snapshot.title.trimmed.isEmpty ? "Unknown Track" : snapshot.title
    }
    
    private func displayArtist(for snapshot: NowPlayingSnapshot) -> String {
        snapshot.artist.trimmed.isEmpty ? "Unknown Artist" : snapshot.artist
    }
    
    private func displayAlbum(for snapshot: NowPlayingSnapshot) -> String {
        snapshot.album.trimmed.isEmpty ? "Unknown Album" : snapshot.album
    }
    
    private func progressValue(elapsedTime: TimeInterval, duration: TimeInterval) -> CGFloat {
        guard duration > 0 else { return 0 }
        return min(max(CGFloat(elapsedTime / duration), 0), 1)
    }
    
    private func formattedTime(_ time: TimeInterval) -> String {
        guard time.isFinite else { return "--:--" }
        
        let totalSeconds = max(0, Int(time.rounded()))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func progressTimeColor(isPrimary: Bool, appearance: NowPlayingAppearanceOptions) -> Color {
        switch appearance.progressTintStyle {
        case .default:
            return .secondary
        case .artwork:
            let nsColor = isPrimary ?
            nowPlayingViewModel.artworkPalette.equalizerHighlightColor :
            nowPlayingViewModel.artworkPalette.equalizerBaseColor
            return Color(nsColor: nsColor)
        case .systemAccent:
            return isPrimary ? .accentColor : .accentColor.opacity(0.7)
        }
    }
    
    private func progressTick(for snapshot: NowPlayingSnapshot) -> TimeInterval {
        snapshot.isPlaying ? 1.0 : 30.0
    }
    
    private func playbackStatusColor(for snapshot: NowPlayingSnapshot) -> Color {
        if nowPlayingViewModel.snapshot == nil {
            return .white.opacity(0.48)
        }
        
        return snapshot.isPlaying ?
        Color(red: 0.97, green: 0.73, blue: 0.32) :
            .white.opacity(0.48)
    }
}

// MARK: - Expanded panel

enum LockScreenMediaPresentation: String, CaseIterable, Identifiable {
    /// Blurred motion art + album cover + lyrics.
    case lyrics
    /// Blurred motion art + album cover, no lyrics.
    case cover
    /// The motion art alone, unblurred.
    case motion

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lyrics: return "Lyrics"
        case .cover:  return "Cover"
        case .motion: return "Motion"
        }
    }
}

struct LockScreenNowPlayingPanelView: View {
    static let panelSize = CGSize(width: 340, height: 180)
    
    private static let expandedPanelHeight: CGFloat = panelSize.height - 20
    private static let expandedArtworkSize: CGFloat = 500
    private static let expandedArtworkSpacing: CGFloat = 90
    private static let expandedStackLift: CGFloat = 160
    private static let expandedClockHeight: CGFloat = 76
    private static let expandedClockArtworkSpacing: CGFloat = 20
    private static let expandedLyricsWidth: CGFloat = 520
    private static let expandedLyricsSpacing: CGFloat = 90
    private static let panelCenterYOffset: CGFloat = (Self.panelSize.height / 2) + 80

    // Expanded composition is screen-relative: clock on top, cover in the
    // middle, player card tucked right underneath.
    private var screenSize: CGSize { screen.frame.size }
    private var artworkSize: CGFloat { min(520, screenSize.height * 0.40) }
    private var clockHeight: CGFloat { max(96, screenSize.height * 0.18) }
    private var clockCoverGap: CGFloat { screenSize.height * 0.032 }
    private var coverPanelGap: CGFloat { screenSize.height * 0.022 }

    /// Blur for the full-screen artwork background. The animated variant is
    /// blurred harder so the slow rotation reads as movement, not as noise.
    private static let animatedBackgroundBlur: CGFloat = 200
    private static let staticBackgroundBlur: CGFloat = 120
    
    let snapshot: NowPlayingSnapshot
    let artworkImage: NSImage?
    let screen: NSScreen
    
    @ObservedObject var settingsViewModel: SettingsViewModel
    @ObservedObject var nowPlayingViewModel: NowPlayingViewModel
    @ObservedObject var lockScreenManager: LockScreenManager
    @ObservedObject var animator: LockScreenPanelAnimator

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    @State private var scrubProgress: CGFloat?
    @State private var onTapArtwork: Bool
    /// Last presentation picked by the user. Empty until they choose one, so
    /// the configured default keeps applying until they override it.
    @AppStorage("lockScreen.mediaPresentation") private var presentationRaw: String = ""
    @State private var motionArtURL: URL?
    @State private var motionArtPreviewURL: URL?
    @State private var backgroundRotation: Double = 0
    @State private var backgroundScale: CGFloat = 1

    /// Watches the pointer so the artwork background can fade to black while
    /// the lock screen sits untouched (see `isBackgroundDimmed`).
    @StateObject private var idleMonitor = SystemIdleMonitor()

    /// Drives the dip-to-black that masks the swap of background treatment
    /// (blur / darkening / saturation) when the presentation changes.
    @State private var presentationFadeVeil: Double = 0

    private let animationTick: TimeInterval = 1.0 / 10.0

    /// Single source of truth for every fade triggered by a presentation
    /// change, so lyrics -> cover -> motion all share one timing curve.
    private var presentationCrossfade: Animation {
        reduceMotion
        ? .easeInOut(duration: 0.20)
        : .spring(response: 0.52, dampingFraction: 0.92)
    }

    private var presentationFadeOut: Animation {
        reduceMotion ? .easeInOut(duration: 0.20) : .easeInOut(duration: 0.36)
    }

    /// Slow dissolve used by the idle fade, so the artwork background is gone
    /// before the eye notices it started moving.
    private var idleFade: Animation {
        reduceMotion ? .easeInOut(duration: 0.45) : .easeInOut(duration: 1.6)
    }
    
    init(
        snapshot: NowPlayingSnapshot,
        artworkImage: NSImage?,
        screen: NSScreen,
        settingsViewModel: SettingsViewModel,
        nowPlayingViewModel: NowPlayingViewModel,
        lockScreenManager: LockScreenManager,
        animator: LockScreenPanelAnimator
    ) {
        self.snapshot = snapshot
        self.artworkImage = artworkImage
        self.screen = screen
        self.settingsViewModel = settingsViewModel
        self.nowPlayingViewModel = nowPlayingViewModel
        self.lockScreenManager = lockScreenManager
        self.animator = animator
        self._onTapArtwork = State(initialValue: settingsViewModel.lockScreen.isLockScreenArtworkExpanded)
    }
    
    var body: some View {
        GeometryReader { screenProxy in
            let screenWidth = screenProxy.size.width
            let screenHeight = screenProxy.size.height
            
            ZStack {
                // Idle state: pure black behind the UI. Cross-fades with the
                // artwork background so the gesture reads as "fade out"
                // instead of revealing the (transparent) lock-screen window.
                Color.black
                    .opacity(isBackgroundDimmed ? 1 : 0)
                    .allowsHitTesting(false)
                    .ignoresSafeArea()

                if onTapArtwork {
                    coverAndBackgroundPresentation
                        .opacity(isBackgroundDimmed ? 0 : 1)
                        .ignoresSafeArea()
                        .transition(.opacity)
                }
                
                if onTapArtwork, presentation != .motion, settingsViewModel.lockScreen.showsClock {
                    expandedClockView
                        .transition(.opacity)
                        .offset(y: expandedClockOffsetY)
                }
                
                if onTapArtwork, presentation != .motion {
                    expandedArtworkButton
                        .transition(.scale(scale: 0.96).combined(with: .opacity))
                        .offset(x: expandedArtworkXOffset, y: 0)
                }
                
                if shouldShowExpandedLyrics {
                    LockScreenLyricsView(
                        nowPlayingViewModel: nowPlayingViewModel,
                        width: Self.expandedLyricsWidth
                    )
                    .transition(.opacity)
                    .offset(x: expandedLyricsXOffset, y: 0)
                }
                
                playerPanel
                    .offset(x: 0, y: playerPanelYOffset(screenHeight: screenHeight))

                if onTapArtwork,
                   settingsViewModel.lockScreen.showsPresentationSwitcher,
                   isBackgroundDimmed == false {
                    VStack(alignment: .leading, spacing: 6) {
                        presentationSwitcher
                    }
                    .padding(.leading, 22)
                    .padding(.top, 20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .transition(.opacity)
                }

                // Cross-fades every presentation swap. The background's blur /
                // darkening / saturation change instantly (they live inside the
                // video view), so this dip keeps that swap from popping.
                Color.black
                    .opacity(presentationFadeVeil)
                    .allowsHitTesting(false)
                    .ignoresSafeArea()
            }
            .frame(width: screenWidth, height: screenHeight)
            .animation(presentationCrossfade, value: presentationRaw)
            .animation(idleFade, value: isBackgroundDimmed)
        }
        .task(id: trackKey) {
            await resolveMotionArt()
        }
        .task {
            // Starts the system volume observer the first time the lock screen
            // appears; calling it again is a no-op.
            VolumeHUDController.shared.start()
        }

        .opacity(animator.isPresented ? 1 : 0)
        .animation(.spring(response: 0.3), value: animator.isPresented)
        .animation(.spring(response: 0.58, dampingFraction: 0.86), value: onTapArtwork)
        .animation(.spring(response: 0.58, dampingFraction: 0.86), value: settingsViewModel.lockScreen.isLockScreenLyricsEnabled)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .environment(\.controlActiveState, .active)
        .onAppear {
            if onTapArtwork != settingsViewModel.lockScreen.isLockScreenArtworkExpanded {
                onTapArtwork = settingsViewModel.lockScreen.isLockScreenArtworkExpanded
            }
            presentationFadeVeil = 0
            syncLyricsPresentationState()
            idleMonitor.start(timeout: idleTimeout)
        }
        .onDisappear {
            nowPlayingViewModel.setLyricsPresentationActive(false)
            idleMonitor.stop()
        }
        .onChange(of: settingsViewModel.lockScreen.idleBackgroundDimSeconds) { _, newValue in
            idleMonitor.updateTimeout(max(0.5, newValue))
        }
        .onChange(of: onTapArtwork) { _, newValue in
            if settingsViewModel.lockScreen.isLockScreenArtworkExpanded != newValue {
                settingsViewModel.lockScreen.isLockScreenArtworkExpanded = newValue
            }
            syncLyricsPresentationState()
        }
        .onChange(of: settingsViewModel.lockScreen.isLockScreenLyricsEnabled) {
            syncLyricsPresentationState()
        }
        .onChange(of: nowPlayingViewModel.snapshot?.lyricsLookupKey) {
            syncLyricsPresentationState()
        }
    }

    private var playerPanel: some View {
        LockScreenNowPlayingView(
            nowPlayingViewModel: nowPlayingViewModel,
            mediaSettings: settingsViewModel.mediaAndFiles,
            onTapArtwork: $onTapArtwork
        )
        .frame(
            width: Self.panelSize.width,
            height: onTapArtwork ? Self.expandedPanelHeight : Self.panelSize.height,
            alignment: .topLeading
        )
        .background {
            panelBackground
        }
        .clipShape(RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous))
        .environment(\.colorScheme, .dark)
        .environment(\.controlActiveState, .active)
        .shadow(color: .black.opacity(0.24), radius: 26, x: 0, y: 14)
    }

    /// Motion art for the big cover. Suppressed in the `.motion` presentation
    /// because there the very same loop already fills the screen.
    private var coverMotionArtURL: URL? {
        presentation == .motion ? nil : motionArtURL
    }

    private var isCoverArtworkPlaying: Bool {
        (nowPlayingViewModel.snapshot?.isPlaying ?? snapshot.isPlaying)
    }

    private var expandedArtworkButton: some View {
        Button(action: {
            withAnimation(.spring(response: 0.65)) {
                onTapArtwork = false
            }
        }) {
            MotionArtworkCover(
                videoURL: coverMotionArtURL,
                isPlaying: isCoverArtworkPlaying,
                size: artworkSize,
                cornerRadius: 14
            ) {
                ArtworkView(
                    nowPlayingViewModel: nowPlayingViewModel,
                    width: artworkSize,
                    height: artworkSize,
                    cornerRadius: 14,
                    usesFlipAnimation: true
                )
            }
            .shadow(color: .black.opacity(0.38), radius: 28, x: 0, y: 18)
        }
        .buttonStyle(PlaybackSourceButtonStyle())
        // Gentle pointer parallax on the big cover. Angles scaled up from the
        // 60 pt thumbnail: 500 pt needs a wider swing to read as motion.
        .artworkPointerMotion(maxTilt: 8, maxOffset: 5, hoverScale: 1.008)
    }

    private var expandedClockView: some View {
        TimelineView(.periodic(from: .now, by: settingsViewModel.lockScreen.showsClockSeconds ? 1 : 30)) { context in
            LockScreenClockView(
                date: context.date,
                width: artworkSize + 160,
                height: clockHeight,
                showsDate: settingsViewModel.lockScreen.showsClockDate,
                dateFormat: settingsViewModel.lockScreen.clockDateFormat,
                showsSeconds: settingsViewModel.lockScreen.showsClockSeconds,
                fontDesign: settingsViewModel.lockScreen.clockFontDesign,
                sizeScale: CGFloat(settingsViewModel.lockScreen.clockSizeScale)
            )
        }
    }

    private var shouldShowExpandedLyrics: Bool {
        onTapArtwork && settingsViewModel.lockScreen.isLockScreenLyricsEnabled && presentation == .lyrics
    }

    // MARK: Idle

    /// Seconds of pointer inactivity before the artwork background fades out.
    private var idleTimeout: TimeInterval {
        max(0.5, settingsViewModel.lockScreen.idleBackgroundDimSeconds)
    }

    /// True while the expanded lock screen should hide its artwork background.
    /// Only the expanded presentation owns a background, so the collapsed
    /// player card keeps sitting on the normal lock screen.
    private var isBackgroundDimmed: Bool {
        onTapArtwork
            && settingsViewModel.lockScreen.isIdleBackgroundDimEnabled
            && idleMonitor.isIdle
    }

    private var presentation: LockScreenMediaPresentation {
        LockScreenMediaPresentation(rawValue: presentationRaw)
            ?? settingsViewModel.lockScreen.defaultMediaPresentation
    }

    private var presentationSwitcher: some View {
        HStack(spacing: 3) {
            ForEach(LockScreenMediaPresentation.allCases) { mode in
                Button {
                    switchPresentation(to: mode)
                } label: {
                    Text(mode.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(presentation == mode ? Color.black.opacity(0.85) : .white.opacity(0.72))
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background {
                            Capsule(style: .continuous)
                                .fill(presentation == mode ? Color.white : Color.clear)
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background {
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: presentationRaw)
    }

    private var expandedArtworkXOffset: CGFloat {
        guard shouldShowExpandedLyrics else { return 0 }
        return -((Self.expandedLyricsWidth + Self.expandedLyricsSpacing) / 2)
    }

    private var expandedLyricsXOffset: CGFloat {
        (artworkSize + Self.expandedLyricsSpacing) / 2
    }

    private var expandedClockOffsetY: CGFloat {
        -(artworkSize / 2 + clockCoverGap + clockHeight / 2)
    }

    private func playerPanelYOffset(screenHeight: CGFloat) -> CGFloat {
        if onTapArtwork {
            return artworkSize / 2 + coverPanelGap + Self.expandedPanelHeight / 2
        } else {
            return Self.panelCenterYOffset + activeMediaPanelVerticalOffset
        }
    }

    private var mediaPanelVerticalOffset: CGFloat {
        CGFloat(settingsViewModel.lockScreen.mediaPanelVerticalOffset)
    }

    private var activeMediaPanelVerticalOffset: CGFloat {
        onTapArtwork ? 0 : mediaPanelVerticalOffset
    }

    private var isShowingMotionArt: Bool { motionArtURL != nil }

    /// Blur for the still-cover fallback.
    ///
    /// This has to be generous. A square album cover has to fill a screen that
    /// is several times its size, so the blur is the only thing standing
    /// between the upscale and the eye — which is exactly why `blurRadius: 0`
    /// in the cover / motion presentations looked like giant blocky pixels.
    private var backgroundBlur: CGFloat {
        let base: CGFloat

        if isShowingMotionArt {
            base = presentation == .lyrics ? 24 : 0
        } else {
            switch presentation {
            case .motion: base = 56
            case .cover:  base = 64
            case .lyrics: base = 48
            }
        }

        return base * backgroundBlurScale
    }

    /// User multiplier for the background blur, 100% = the tuned default.
    private var backgroundBlurScale: CGFloat {
        CGFloat(settingsViewModel.lockScreen.backgroundBlurScale) / 100
    }

    private var backgroundDarkening: Double {
        let base: Double

        if isShowingMotionArt {
            base = presentation == .motion ? 0.10 : 0.34
        } else {
            base = presentation == .motion ? 0.22 : 0.34
        }

        return min(0.92, base + settingsViewModel.lockScreen.backgroundDimming / 100)
    }

    private var backgroundSaturation: Double {
        guard isShowingMotionArt else {
            return presentation == .motion ? 0.90 : 0.62
        }
        return presentation == .motion ? 1.0 : 0.62
    }

    private var backgroundBrightness: Double {
        guard isShowingMotionArt else {
            return presentation == .motion ? -0.04 : -0.10
        }
        return presentation == .motion ? 0 : -0.06
    }

    private var coverAndBackgroundPresentation: some View {
        GeometryReader { proxy in
            let diagonal = hypot(proxy.size.width, proxy.size.height)
            ZStack {
                Color.black

                if isShowingMotionArt || resolvedArtworkImage != nil {
                    MotionArtworkBackground(
                        videoURL: motionArtURL,
                        previewURL: motionArtPreviewURL,
                        artwork: resolvedArtworkImage,
                        isPlaying: (nowPlayingViewModel.snapshot?.isPlaying ?? snapshot.isPlaying) && !reduceMotion,
                        // A real motion loop is already soft, so it can sit
                        // behind the UI nearly untouched. A still cover has to
                        // be blurred hard or the upscale reads as giant pixels
                        // — MotionArtworkBackground tiles it for the same reason.
                        blurRadius: backgroundBlur,
                        darkening: backgroundDarkening,
                        saturation: backgroundSaturation,
                        brightness: backgroundBrightness
                    )
                    // Safe to oversize even for the still path: it is tiled, so
                    // the frame size no longer drives the magnification.
                    .frame(width: diagonal, height: diagonal)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .onAppear(perform: configureMediaPanelBackgroundAnimation)
            .onChange(of: isAnimatedArtworkBackground) {
                configureMediaPanelBackgroundAnimation()
            }
        }
    }

    /// The expanded screen always fills itself with the current artwork.
    /// It breathes and drifts when nothing forbids movement, and sits still
    /// (still filling the screen) when Reduce Motion is on.
    private var isAnimatedArtworkBackground: Bool {
        !reduceMotion
    }

    private var mediaPanelBackgroundScale: CGFloat {
        isAnimatedArtworkBackground ? backgroundScale : 1
    }

    private var mediaPanelBackgroundRotation: Angle {
        isAnimatedArtworkBackground ? .degrees(backgroundRotation) : .zero
    }

    private func configureMediaPanelBackgroundAnimation() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            backgroundRotation = 0
            backgroundScale = 1
        }

        guard isAnimatedArtworkBackground else {
            return
        }

        withAnimation(.linear(duration: 24).repeatForever(autoreverses: false)) {
            backgroundRotation = 360
        }

        withAnimation(.easeInOut(duration: 8).repeatForever(autoreverses: true)) {
            backgroundScale = 1.35
        }
    }

    private var panelCornerRadius: CGFloat {
        CGFloat(settingsViewModel.lockScreen.panelCornerRadius)
    }

    @ViewBuilder
    private var panelBackground: some View {
        LockScreenWidgetSurface(
            style: settingsViewModel.lockScreen.widgetAppearanceStyle,
            tintStyle: settingsViewModel.lockScreen.widgetTintStyle,
            cornerRadius: panelCornerRadius,
            liquidGlassVariant: settingsViewModel.lockScreen.liquidGlassVariant
        )
    }

    private var trackKey: String {
        let title = nowPlayingViewModel.snapshot?.title ?? snapshot.title
        let artist = nowPlayingViewModel.snapshot?.artist ?? snapshot.artist
        return "\(title)|\(artist)"
    }

    private func resolveMotionArt() async {
        let title = nowPlayingViewModel.snapshot?.title ?? snapshot.title
        let artist = nowPlayingViewModel.snapshot?.artist ?? snapshot.artist

        let isEnabled = UserDefaults.standard.object(forKey: "AppleMusicMotionEnabled") as? Bool ?? true

        guard isEnabled, !title.isEmpty, title != "Nothing Playing" else {
            motionArtURL = nil
            motionArtPreviewURL = nil
            return
        }

        // Apple Music motion artwork needs no credentials, so a miss simply
        // falls back to the still cover in MotionArtworkBackground.
        let result = await AppleMusicMotionService.shared.motionArt(
            title: title,
            artist: artist,
            cacheKey: trackKey
        )

        if motionArtURL != result.videoURL {
            motionArtURL = result.videoURL
        }
        if motionArtPreviewURL != result.previewURL {
            motionArtPreviewURL = result.previewURL
        }
    }

    private var resolvedArtworkImage: NSImage? {
        artworkImage ?? nowPlayingViewModel.artworkImage
    }

    private func syncLyricsPresentationState() {
        nowPlayingViewModel.setLyricsPresentationActive(shouldShowExpandedLyrics)
    }

    /// Dims the stack out, swaps the presentation underneath, then fades it
    /// back in. The background's blur / darkening / saturation are not
    /// animatable, so the actual state change happens while the veil is
    /// opaque. Reduce Motion swaps straight away with a short crossfade.
    private func switchPresentation(to mode: LockScreenMediaPresentation) {
        guard mode.rawValue != presentationRaw else { return }

        guard onTapArtwork, !reduceMotion else {
            withAnimation(presentationCrossfade) {
                presentationRaw = mode.rawValue
                presentationFadeVeil = 0
            }
            return
        }

        withAnimation(.easeOut(duration: 0.15)) {
            presentationFadeVeil = 1
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 160_000_000)
            withAnimation(presentationCrossfade) {
                presentationRaw = mode.rawValue
            }
            withAnimation(presentationFadeOut) {
                presentationFadeVeil = 0
            }
        }
    }
}
