//
//  LockScreenLyricsView.swift
//  DynamicNotch
//
//  Created by Евгений Петрукович on 5/13/26.
//
//  Apple Music-style lyrics, with a self-contained fallback loader: if the
//  view model reports `.failed` / `.notFound` (or has no lines), this view
//  fetches the lyrics itself straight from LRCLib and renders them with the
//  same styling. The view model's data always wins when it has lines.
//

import SwiftUI
internal import AppKit
import Combine

// MARK: - Style tokens

enum LockScreenLyricsStyle {
    static let fontSize: CGFloat = 34
    static let fontWeight: Font.Weight = .bold
    static let lineSpacing: CGFloat = 4
    static let tracking: CGFloat = -0.45
    static let lineGap: CGFloat = 18

    static let lineHPadding: CGFloat = 12
    static let lineVPadding: CGFloat = 7
    static let cornerRadius: CGFloat = 12

    static let lineSpring = Animation.spring(response: 0.46, dampingFraction: 0.84)
    static let scrollSpring = Animation.spring(response: 0.42, dampingFraction: 0.92)

    static let glowCoreOpacity: Double = 0.55
    static let glowBloomOpacity: Double = 0.30

    static func emphasis(distance: Int) -> (opacity: Double, blur: CGFloat, scale: CGFloat) {
        switch distance {
        case 0:  return (1.00, 0.0, 1.000)
        case 1:  return (0.55, 0.7, 0.972)
        case 2:  return (0.34, 1.4, 0.956)
        case 3:  return (0.22, 1.9, 0.944)
        default: return (max(0.12, 0.22 - Double(distance - 3) * 0.03),
                          min(2.8, 1.9 + CGFloat(distance - 3) * 0.3),
                          max(0.925, 0.944 - CGFloat(distance - 3) * 0.004))
        }
    }
}

// MARK: - View

struct LockScreenLyricsView: View {
    @ObservedObject var nowPlayingViewModel: NowPlayingViewModel

    let width: CGFloat
    private let height: CGFloat = 520

    @StateObject private var fallback = LockScreenLyricsFallback()
    @State private var clock = LockScreenLyricsClock()

    /// Shown in the corner of the panel so the source and the ticking clock are
    /// visible on screen. Set to false once everything works.
    static let showsDiagnostics = true

    /// When no provider has timestamps, spread the plain lines across the
    /// track duration so they still advance and scroll. Approximate, not
    /// real sync — set to false to leave such lyrics static.
    static let estimatesTimingsWhenUnavailable = false

    /// How far ahead of a line's timestamp it lights up. Compensates for the
    /// tick interval plus the scroll spring, so the highlight lands on the beat
    /// instead of trailing it.
    private static let timingLead: TimeInterval = 0.14

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { context in
            content(at: context.date)
                .frame(width: width, height: height, alignment: .leading)
                .clipped()
                .mask { fadeMask }
        }
        .overlay(alignment: .topLeading) {
            if Self.showsDiagnostics {
                Text(diagnosticText)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(6)
                    .allowsHitTesting(false)
            }
        }
        .onAppear(perform: loadFallbackIfNeeded)
        .onChange(of: nowPlayingViewModel.snapshot?.lyricsLookupKey) { _, _ in
            loadFallbackIfNeeded()
        }
    }

    // MARK: Content

    @ViewBuilder
    private func content(at date: Date) -> some View {
        let elapsed = clock.elapsed(
            reported: nowPlayingViewModel.elapsedTime(at: date),
            isPlaying: nowPlayingViewModel.snapshot?.isPlaying ?? false,
            at: date
        ) + Self.timingLead

        // Priority: anything with timestamps wins, whoever supplied it. The
        // view model's plain lyrics only show if no synced source has them.
        if let synced = syncedLines {
            LockScreenSyncedLyricsContent(
                lines: synced,
                elapsed: elapsed,
                width: width,
                height: height,
                onSeek: { nowPlayingViewModel.seek(to: $0) }
            )
        } else if let plain = plainLines {
            FallbackLyricsList(lines: plain, width: width, height: height)
        } else {
            switch fallback.phase {
            case .loading, .idle:
                LockScreenLyricsLoadingView(width: width, height: height)

            case .failed(let reason):
                unavailable(title: "The lyrics didn't load", detail: reason)

            case .loaded:
                unavailable(title: "The lyrics were not found")
            }
        }
    }

    /// Timed lines from the view model (when it says the lyrics are synced) or
    /// from the fallback loader — whichever exists.
    private var syncedLines: [LockScreenLyricsFallback.Line]? {
        if case .loaded(let lyrics) = nowPlayingViewModel.lyricsState,
           lyrics.isSynced,
           lyrics.lines.contains(where: { $0.startTime != nil }) {
            return lyrics.lines.map {
                .init(id: $0.id, text: $0.text, startTime: $0.startTime)
            }
        }

        if case .loaded(let lines) = fallback.phase,
           lines.contains(where: { $0.startTime != nil }) {
            return lines
        }

        return nil
    }

    /// Untimed lines, only used when nothing synced is available.
    private var plainLines: [LockScreenLyricsFallback.Line]? {
        if case .loaded(let lyrics) = nowPlayingViewModel.lyricsState, !lyrics.lines.isEmpty {
            return lyrics.lines.map {
                .init(id: $0.id, text: $0.text, startTime: nil)
            }
        }

        if case .loaded(let lines) = fallback.phase, !lines.isEmpty {
            return lines.map { .init(id: $0.id, text: $0.text, startTime: nil) }
        }

        return nil
    }

    private var diagnosticText: String {
        let lines = syncedLines?.count ?? plainLines?.count ?? 0
        let synced = syncedLines != nil
        let source = fallback.source.isEmpty ? "-" : fallback.source
        let modelState: String
        switch nowPlayingViewModel.lyricsState {
        case .loaded(let lyrics): modelState = lyrics.isSynced ? "vm-synced" : "vm-plain"
        case .failed: modelState = "vm-failed"
        case .notFound: modelState = "vm-notfound"
        case .loading: modelState = "vm-loading"
        case .idle: modelState = "vm-idle"
        }
        let t = String(format: "%.1f", clock.lastElapsed)
        let trace = fallback.trace.isEmpty ? "-" : fallback.trace
        return "\(synced ? "SYNCED" : "PLAIN") · \(source) · \(lines) lines · t=\(t) · \(modelState) · clock=\(clock.usesLocalClock ? "local" : "vm")\n\(trace)"
    }

    private var fadeMask: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.16),
                .init(color: .black, location: 0.86),
                .init(color: .clear, location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func unavailable(
        title: String,
        detail: String? = nil,
        systemImage: String = "quote.bubble"
    ) -> some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(.white.opacity(0.28))

            Text(title)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white.opacity(0.4))
                .multilineTextAlignment(.center)

            if let detail {
                Text(detail)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.28))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }
        }
        .frame(width: width, height: height, alignment: .center)
    }

    // MARK: Fallback loading

    private func loadFallbackIfNeeded() {
        guard let snapshot = nowPlayingViewModel.snapshot else { return }
        fallback.loadIfNeeded(
            title: snapshot.title,
            artist: snapshot.artist,
            album: snapshot.album,
            duration: snapshot.duration
        )
    }
}

// MARK: - Clock

/// The highlight is only as good as the elapsed time feeding it. If the view
/// model's value stops advancing while the track is playing, this keeps a local
/// wall-clock estimate instead so the lyrics don't freeze on one line.
final class LockScreenLyricsClock {
    private(set) var usesLocalClock = false
    private(set) var lastElapsed: TimeInterval = 0

    private var previousReported: TimeInterval = -1
    private var frozenTicks = 0
    private var anchorElapsed: TimeInterval = 0
    private var anchorDate = Date()

    func elapsed(reported: TimeInterval, isPlaying: Bool, at date: Date) -> TimeInterval {
        if abs(reported - previousReported) < 0.02 {
            frozenTicks += 1
        } else {
            frozenTicks = 0
            if usesLocalClock, reported > anchorElapsed + 0.5 {
                // A seek or a track change: adopt the new position.
                anchorElapsed = reported
                anchorDate = date
            }
        }
        previousReported = reported

        // ~0.6 s without movement while playing: trust the wall clock instead.
        if frozenTicks >= 6, isPlaying {
            usesLocalClock = true
        }
        if !isPlaying {
            usesLocalClock = false
            anchorElapsed = reported
            anchorDate = date
        }

        let value: TimeInterval
        if usesLocalClock {
            value = anchorElapsed + date.timeIntervalSince(anchorDate)
        } else {
            anchorElapsed = reported
            anchorDate = date
            value = reported
        }

        lastElapsed = value
        return value
    }
}

// MARK: - Synced list

private struct LockScreenSyncedLyricsContent: View {
    let lines: [LockScreenLyricsFallback.Line]
    let elapsed: TimeInterval
    let width: CGFloat
    let height: CGFloat
    let onSeek: (TimeInterval) -> Void

    private var activeIndex: Int {
        let timed = lines.filter { $0.startTime != nil }
        guard !timed.isEmpty else { return 0 }

        var result = 0
        for (offset, line) in lines.enumerated() {
            guard let start = line.startTime else { continue }
            if start <= elapsed {
                result = offset
            } else {
                break
            }
        }
        return result
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: LockScreenLyricsStyle.lineGap) {
                    ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                        LockScreenLyricRow(
                            text: line.text,
                            distanceFromActive: index - activeIndex,
                            onTap: line.startTime.map { start in
                                { onSeek(start) }
                            }
                        )
                        .id(line.id)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, height * 0.42)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: width, height: height)
            .onChange(of: activeIndex) { _, newIndex in
                withAnimation(LockScreenLyricsStyle.scrollSpring) {
                    proxy.scrollTo(lines.indices.contains(newIndex) ? lines[newIndex].id : nil,
                                   anchor: .center)
                }
            }
        }
    }
}

// MARK: - Plain list

private struct FallbackLyricsList: View {
    let lines: [LockScreenLyricsFallback.Line]
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: LockScreenLyricsStyle.lineGap) {
                ForEach(lines) { line in
                    Text(line.text)
                        .font(.system(size: LockScreenLyricsStyle.fontSize,
                                      weight: LockScreenLyricsStyle.fontWeight))
                        .tracking(LockScreenLyricsStyle.tracking)
                        .lineSpacing(LockScreenLyricsStyle.lineSpacing)
                        .foregroundStyle(.white.opacity(0.82))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, LockScreenLyricsStyle.lineHPadding)
                }
            }
            .padding(.vertical, 40)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: width, height: height)
    }
}

// MARK: - Row

private struct LockScreenLyricRow: View {
    let text: String
    let distanceFromActive: Int
    let onTap: (() -> Void)?

    @State private var isHovered = false

    private var isActive: Bool { distanceFromActive == 0 }
    private var distance: Int { abs(distanceFromActive) }

    private var emphasis: (opacity: Double, blur: CGFloat, scale: CGFloat) {
        if isActive { return (1.0, 0.0, 1.0) }
        let base = LockScreenLyricsStyle.emphasis(distance: distance)
        if isHovered {
            return (max(base.opacity, 0.82), max(base.blur - 0.6, 0), base.scale - 0.006)
        }
        return base
    }

    private var lineText: some View {
        Text(text)
            .font(.system(size: LockScreenLyricsStyle.fontSize,
                          weight: LockScreenLyricsStyle.fontWeight))
            .tracking(LockScreenLyricsStyle.tracking)
            .lineSpacing(LockScreenLyricsStyle.lineSpacing)
            .foregroundStyle(.white)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func glow(radius: CGFloat, opacity: Double) -> some View {
        lineText
            .blur(radius: isActive ? radius : 0)
            .opacity(isActive ? opacity : 0)
            .blendMode(.plusLighter)
            .allowsHitTesting(false)
    }

    var body: some View {
        ZStack(alignment: .leading) {
            glow(radius: 7, opacity: LockScreenLyricsStyle.glowCoreOpacity)
            glow(radius: 20, opacity: LockScreenLyricsStyle.glowBloomOpacity)
            lineText
        }
        .compositingGroup()
        .opacity(emphasis.opacity)
        .blur(radius: emphasis.blur)
        .padding(.horizontal, LockScreenLyricsStyle.lineHPadding)
        .padding(.vertical, LockScreenLyricsStyle.lineVPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .scaleEffect(emphasis.scale, anchor: .leading)
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
        .onHover { hovering in
            guard onTap != nil else { return }
            isHovered = hovering
        }
        .animation(LockScreenLyricsStyle.lineSpring, value: isActive)
        .animation(.spring(response: 0.25, dampingFraction: 0.88), value: isHovered)
    }
}

// MARK: - Loading

private struct LockScreenLyricsLoadingView: View {
    let width: CGFloat
    let height: CGFloat

    @State private var shimmerPhase: CGFloat = -0.6

    private let lineWidths: [CGFloat] = [0.58, 0.86, 0.94, 0.70, 0.48]

    var body: some View {
        VStack(alignment: .leading, spacing: LockScreenLyricsStyle.lineGap) {
            ForEach(0..<5, id: \.self) { index in
                let isActive = index == 2

                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.white.opacity(isActive ? 0.30 : 0.14))
                    .frame(
                        width: (width - 48) * lineWidths[index],
                        height: isActive ? 32 : 22
                    )
                    .blur(radius: isActive ? 0 : CGFloat(abs(index - 2)) * 0.6)
            }
        }
        .frame(width: width, height: height, alignment: .center)
        .mask(
            LinearGradient(
                colors: [.black.opacity(0.25), .black, .black.opacity(0.25)],
                startPoint: UnitPoint(x: shimmerPhase - 0.5, y: 0.5),
                endPoint: UnitPoint(x: shimmerPhase + 0.5, y: 0.5)
            )
        )
        .onAppear {
            withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) {
                shimmerPhase = 1.6
            }
        }
    }
}

// MARK: - Fallback loader

@MainActor
final class LockScreenLyricsFallback: ObservableObject {
    struct Line: Identifiable, Equatable {
        let id: Int
        let text: String
        let startTime: TimeInterval?
    }

    enum Phase: Equatable {
        case idle
        case loading
        case loaded([Line])
        /// Nothing to render, with the reason (network error, no match, …).
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var source: String = ""
    @Published private(set) var trace: String = ""

    private var key = ""
    private var task: Task<Void, Never>?
    /// Track key -> parsed lines, so switching back to a song is instant and
    /// an LRCLib outage doesn't wipe lyrics you already have.
    private var cache: [String: [Line]] = [:]

    func loadIfNeeded(title: String, artist: String, album: String, duration: TimeInterval) {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let performer = artist.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !name.isEmpty, name != "Unknown Track" else { return }

        let newKey = [name, performer, album, String(Int(duration.rounded()))].joined(separator: "|")
        guard newKey != key else { return }

        key = newKey
        task?.cancel()

        if let cached = cache[newKey], !cached.isEmpty {
            phase = .loaded(cached)
            return
        }

        phase = .loading

        task = Task { [weak self] in
            let result = await Self.fetch(name: name, artist: performer, album: album, duration: duration)
            guard !Task.isCancelled, let self else { return }
            if result.lines.isEmpty {
                print("[Lyrics] fallback empty for \(name) — \(result.reason ?? "no reason")")
                self.trace = result.trace
                self.phase = .failed(result.reason ?? "No lyrics found for this track")
            } else {
                var lines = result.lines
                var source = result.source

                if Self.needsEstimate(lines), LockScreenLyricsView.estimatesTimingsWhenUnavailable {
                    lines = Self.estimate(lines, duration: duration)
                    source = source + "+est"
                    print("[Lyrics] estimated timings for \(lines.count) lines from \(source)")
                }

                print("[Lyrics] fallback loaded \(lines.count) lines from \(source) for \(name)")
                self.source = source
                self.trace = result.trace
                self.phase = .loaded(lines)
                self.cache[newKey] = result.lines
            }
        }
    }

    // MARK: Estimated timings

    private static func needsEstimate(_ lines: [Line]) -> Bool {
        !lines.isEmpty && lines.allSatisfy { $0.startTime == nil }
    }

    /// Spreads lines across the track, weighting each by its length so longer
    /// lines hold the screen longer. Leaves ~8 % at the end for the outro.
    private static func estimate(_ lines: [Line], duration: TimeInterval) -> [Line] {
        guard duration > 20, lines.count > 1 else { return lines }

        let weights = lines.map { Double(max(4, $0.text.count)) }
        let total = weights.reduce(0, +)
        let usable = duration * 0.90
        var cursor = duration * 0.03

        return lines.enumerated().map { index, line in
            let start = cursor
            cursor += usable * (weights[index] / total)
            return Line(id: index, text: line.text, startTime: start)
        }
    }

    // MARK: Networking

    private struct Payload: Decodable {
        let syncedLyrics: String?
        let plainLyrics: String?
        let trackName: String?
        let artistName: String?
    }

    /// Result of a lookup plus why it came back empty.
    private struct Lookup {
        var lines: [Line] = []
        var reason: String?
        var source: String = "none"
        /// Compact per-provider outcome, e.g. "lrclib:502 kugou:nosong ovh:ok".
        var trace: String = ""
    }

    private struct OVHLyrics: Decodable {
        let lyrics: String
    }

    private struct TextylLine: Decodable {
        let seconds: Double
        let lyrics: String
    }

    private static func fetch(
        name: String,
        artist: String,
        album: String,
        duration: TimeInterval
    ) async -> Lookup {
        // 1. LRCLib exact match (best: gives synced lines).
        var exact: [URLQueryItem] = [
            .init(name: "track_name", value: name),
            .init(name: "artist_name", value: artist)
        ]
        if !album.isEmpty { exact.append(.init(name: "album_name", value: album)) }
        if duration >= 1 { exact.append(.init(name: "duration", value: String(Int(duration.rounded())))) }

        let exactResult: (Payload?, String?) = await get(url: lrclibURL(path: "/api/get", items: exact))
        if let payload = exactResult.0, let lines = lines(from: payload), !lines.isEmpty {
            return Lookup(lines: lines, source: "lrclib-get")
        }
        var reason = exactResult.1
        var trace: [String] = ["lrclib:\(code(exactResult.1))"]

        // 2. LRCLib search (looser, still synced when available).
        let searchURL = lrclibURL(
            path: "/api/search",
            items: [.init(name: "q", value: "\(name) \(artist)".trimmingCharacters(in: .whitespaces))]
        )
        let found: ([Payload]?, String?) = await get(url: searchURL)
        trace.append("search:\(code(found.1))")
        if let payloads = found.0 {
            for payload in payloads {
                if let lines = lines(from: payload), !lines.isEmpty {
                    return Lookup(lines: lines, source: "lrclib-search", trace: trace.joined(separator: " "))
                }
            }
            reason = reason ?? "No match on LRCLib for “\(name)”"
        } else {
            reason = reason ?? found.1
        }

        // 3. LRCLib search by fields — a different code path on their side, so
        //    it sometimes answers while `q=` is erroring.
        let fieldsURL = lrclibURL(
            path: "/api/search",
            items: [
                .init(name: "track_name", value: name),
                .init(name: "artist_name", value: artist)
            ]
        )
        let byFields: ([Payload]?, String?) = await get(url: fieldsURL)
        trace.append("fields:\(code(byFields.1))")
        if let payloads = byFields.0 {
            for payload in payloads {
                if let lines = lines(from: payload), !lines.isEmpty {
                    return Lookup(lines: lines, source: "lrclib-fields")
                }
            }
        }

        // 4. lrc.red / Apple Music TTML — line or word level timing.
        let lrcRed = await lrcRedLyrics(name: name, artist: artist, album: album, duration: duration)
        trace.append("lrc.red:\(lrcRed.1)")
        if let lines = lrcRed.0, !lines.isEmpty {
            return Lookup(lines: lines, source: "lrc.red", trace: trace.joined(separator: " "))
        }

        // 5. Kugou — independent of LRCLib, returns real LRC timings.
        let kugou = await kugouLyrics(name: name, artist: artist)
        if let lines = kugou.0, !lines.isEmpty {
            return Lookup(lines: lines, source: "kugou", trace: trace.joined(separator: " ") + " kugou:ok")
        }

        // 6. textyl — smaller catalogue, and its host has been unreliable.
        if let lines = await textylLyrics(name: name, artist: artist), !lines.isEmpty {
            return Lookup(lines: lines, source: "textyl", trace: trace.joined(separator: " ") + " textyl:ok")
        }

        // 7. lyrics.ovh — plain text only, last resort.
        let plain = await plainLyrics(name: name, artist: artist)
        let fullTrace = (trace + ["kugou:\(kugou.1)", "ovh:\(plain.0 == nil ? "miss" : "ok")"]).joined(separator: " ")
        if let lines = plain.0, !lines.isEmpty {
            return Lookup(lines: lines, source: "lyrics.ovh", trace: fullTrace)
        }

        return Lookup(reason: reason ?? "No lyrics found for “\(name)”", trace: fullTrace)
    }

    private static func code(_ message: String?) -> String {
        guard let message else { return "miss" }
        if let range = message.range(of: "HTTP ") {
            return String(message[range.upperBound...].prefix(3))
        }
        if message.lowercased().contains("no match") { return "miss" }
        return "err"
    }

    private static func lrclibURL(path: String, items: [URLQueryItem]) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "lrclib.net"
        components.path = path
        components.queryItems = items
        return components.url
    }

    private static func makeRequest(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("DynamicNotch/1.0 (https://github.com)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    /// Retries 5xx once — LRCLib returns 502/503 when it is under load, and a
    /// single failing request should not empty the panel.
    private static func get<T: Decodable>(url: URL?) async -> (T?, String?) {
        guard let url else { return (nil, "Could not build the request URL") }

        let service = url.host?.replacingOccurrences(of: "www.", with: "") ?? "the lyrics service"
        var lastMessage: String?

        for attempt in 0..<2 {
            do {
                let (data, response) = try await URLSession.shared.data(for: makeRequest(url))
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                print("[Lyrics] GET \(url.path) -> \(status) (attempt \(attempt + 1))")

                if status == 200 {
                    return (try JSONDecoder().decode(T.self, from: data), nil)
                }

                lastMessage = status >= 500
                    ? "\(service) is having trouble (HTTP \(status))"
                    : "\(service) returned HTTP \(status)"

                if status < 500 { return (nil, lastMessage) }
            } catch {
                print("[Lyrics] GET \(url.path) failed: \(error)")
                lastMessage = describe(error)
            }

            if attempt == 0 {
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }

        return (nil, lastMessage)
    }

    private struct LrcRedResponse: Decodable {
        struct Item: Decodable {
            let trackName: String?
            let artistName: String?
            let duration: Double?
            let timingType: String?
            let lyricsUrl: String?

            enum CodingKeys: String, CodingKey {
                case trackName = "track_name"
                case artistName = "artist_name"
                case duration
                case timingType = "timing_type"
                case lyricsUrl = "lyricsUrl"
            }
        }

        let results: [Item]
    }

    /// lrc.red serves Apple Music's TTML, which carries real line (sometimes
    /// word) timing. This is the highest-quality synced source available.
    private static func lrcRedLyrics(
        name: String,
        artist: String,
        album: String,
        duration: TimeInterval
    ) async -> ([Line]?, String) {
        var items: [URLQueryItem] = [
            .init(name: "title", value: name),
            .init(name: "artist", value: artist)
        ]
        if !album.isEmpty { items.append(.init(name: "album", value: album)) }
        if duration >= 1 { items.append(.init(name: "duration", value: String(Int(duration.rounded())))) }

        guard let url = makeURL(host: "lyrics-api.binimum.org", path: "/api/get", items: items) else {
            return (nil, "nourl")
        }

        let result: (LrcRedResponse?, String?) = await get(url: url)
        guard let results = result.0?.results, !results.isEmpty else {
            return (nil, code(result.1))
        }

        let timed = results.compactMap { item -> (item: LrcRedResponse.Item, score: Double)? in
            guard let type = item.timingType, type == "line" || type == "word", item.lyricsUrl != nil else {
                return nil
            }
            let score = matchScore(
                title: item.trackName ?? "",
                artist: item.artistName ?? "",
                duration: item.duration ?? duration,
                wantedTitle: name,
                wantedArtist: artist,
                wantedDuration: duration
            )
            return (item, score)
        }
        .sorted { $0.score > $1.score }

        guard let best = timed.first else { return (nil, "notimed") }
        guard best.score >= matchThreshold else {
            print("[Lyrics] lrc.red best match scored \(best.score) — rejected")
            return (nil, "lowmatch")
        }

        for candidate in timed.prefix(3).filter({ $0.score >= best.score - 8 }) {
            guard let string = candidate.item.lyricsUrl, let ttmlURL = URL(string: string) else { continue }
            guard let data = await rawData(ttmlURL),
                  let ttml = String(data: data, encoding: .utf8) else { continue }

            let lines = parseTTML(ttml)
            if !lines.isEmpty {
                print("[Lyrics] lrc.red supplied \(lines.count) timed lines")
                return (lines, "ok")
            }
        }

        return (nil, "notimed")
    }

    /// Minimum score before a provider result is trusted. Below this it is
    /// usually a different song by the same artist, so we reject instead of
    /// showing someone else's lyrics.
    private static let matchThreshold: Double = 62

    private static func matchScore(
        title: String,
        artist: String,
        duration: TimeInterval,
        wantedTitle: String,
        wantedArtist: String,
        wantedDuration: TimeInterval
    ) -> Double {
        let candidateTitle = normalized(title)
        let wanted = normalized(wantedTitle)
        let candidateArtist = normalized(artist)
        let wantedArt = normalized(wantedArtist)

        var score: Double = 0

        if !wanted.isEmpty, candidateTitle == wanted {
            score += 60
        } else if !wanted.isEmpty, candidateTitle.contains(wanted) || wanted.contains(candidateTitle) {
            score += 38
        } else {
            score += 30 * tokenOverlap(candidateTitle, wanted)
        }

        if !wantedArt.isEmpty, !candidateArtist.isEmpty {
            if candidateArtist == wantedArt || candidateArtist.contains(wantedArt) || wantedArt.contains(candidateArtist) {
                score += 30
            } else {
                score += 18 * tokenOverlap(candidateArtist, wantedArt)
            }
        }

        if wantedDuration >= 1, duration > 0 {
            score -= min(25, abs(duration - wantedDuration) * 3)
        }

        return score
    }

    private static func tokenOverlap(_ lhs: String, _ rhs: String) -> Double {
        let a = Set(lhs.split(separator: " ").map(String.init))
        let b = Set(rhs.split(separator: " ").map(String.init))
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        return Double(a.intersection(b).count) / Double(max(a.count, b.count))
    }

    /// Lowercase, drop brackets/feat/suffixes and punctuation so
    /// "Blinding Lights (Remastered 2011)" matches "Blinding Lights".
    private static func normalized(_ value: String) -> String {
        var text = value.lowercased()
        text = text.replacingOccurrences(of: "\\([^)]*\\)", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "\\[[^\\]]*\\]", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "\\b(feat|ft|featuring)\\.?\\s.*$", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "\\s-\\s.*$", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "[^a-z0-9 ]", with: " ", options: .regularExpression)

        let noise: Set<String> = [
            "remastered", "remaster", "version", "edit", "radio", "explicit",
            "deluxe", "album", "single", "live", "mono", "stereo"
        ]
        let words = text.split(separator: " ").map(String.init).filter { !noise.contains($0) && !$0.isEmpty }
        return words.joined(separator: " ")
    }

    private static func rawData(_ url: URL) async -> Data? {
        do {
            let (data, response) = try await URLSession.shared.data(for: makeRequest(url))
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            print("[Lyrics] GET \(url.host ?? "") \(url.path) -> \(status)")
            return status == 200 ? data : nil
        } catch {
            print("[Lyrics] GET \(url.host ?? "") failed: \(error)")
            return nil
        }
    }

    /// <p begin="27.395">…<span>…</span>…</p>
    private static func parseTTML(_ xml: String) -> [Line] {
        guard let regex = try? NSRegularExpression(
            pattern: "<p\\b([^>]*)>(.*?)</p>",
            options: [.dotMatchesLineSeparators]
        ) else { return [] }

        let ns = xml as NSString
        var lines: [Line] = []

        for match in regex.matches(in: xml, range: NSRange(location: 0, length: ns.length)) {
            let attributes = ns.substring(with: match.range(at: 1))
            let body = ns.substring(with: match.range(at: 2))

            guard let beginRange = attributes.range(of: "begin=\""),
                  let endQuote = attributes[beginRange.upperBound...].firstIndex(of: "\""),
                  let start = seconds(String(attributes[beginRange.upperBound..<endQuote]))
            else { continue }

            let text = plainText(from: body)
            guard !text.isEmpty else { continue }

            lines.append(Line(id: lines.count, text: text, startTime: start))
        }

        return lines
            .sorted { ($0.startTime ?? 0) < ($1.startTime ?? 0) }
            .enumerated()
            .map { Line(id: $0.offset, text: $0.element.text, startTime: $0.element.startTime) }
    }

    private static func plainText(from markup: String) -> String {
        var text = markup.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let entities = [
            "&amp;": "&", "&#39;": "'", "&apos;": "'", "&quot;": "\"",
            "&lt;": "<", "&gt;": ">", "&nbsp;": " "
        ]
        for (entity, replacement) in entities {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }
        return text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// TTML times: "27.395", "00:00:27.395", "1:02.5".
    private static func seconds(_ value: String) -> TimeInterval? {
        let parts = value.split(separator: ":")
        guard !parts.isEmpty, parts.count <= 3 else { return nil }

        var total: TimeInterval = 0
        for part in parts {
            guard let number = Double(part.replacingOccurrences(of: ",", with: ".")) else { return nil }
            total = total * 60 + number
        }
        return total
    }

    private static func makeURL(host: String, path: String, items: [URLQueryItem]) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = path
        components.queryItems = items
        return components.url
    }

    /// JSONSerialization rather than Codable: these endpoints type their ids as
    /// string in one response and number in the next.
    private static func rawJSON(_ url: URL) async -> Any? {
        do {
            let (data, response) = try await URLSession.shared.data(for: makeRequest(url))
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            print("[Lyrics] GET \(url.host ?? "") \(url.path) -> \(status)")
            guard status == 200 else { return nil }
            return try JSONSerialization.jsonObject(with: data)
        } catch {
            print("[Lyrics] GET \(url.host ?? "") \(url.path) failed: \(error)")
            return nil
        }
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    /// Kugou: song search → lyric candidates (needs the song hash) → LRC
    /// download, base64 encoded. Independent of LRCLib.
    private static func kugouLyrics(name: String, artist: String) async -> ([Line]?, String) {
        let query = "\(artist) \(name)".trimmingCharacters(in: .whitespaces)

        guard let searchURL = makeURL(
            host: "mobileservice.kugou.com",
            path: "/api/v3/search/song",
            items: [
                .init(name: "format", value: "json"),
                .init(name: "keyword", value: query),
                .init(name: "page", value: "1"),
                .init(name: "pagesize", value: "5")
            ]
        ) else { return (nil, "nourl") }

        var songs: [[String: Any]] = []
        if let root = await rawJSON(searchURL) as? [String: Any],
           let data = root["data"] as? [String: Any],
           let info = data["info"] as? [[String: Any]] {
            songs = info
        }

        // Second attempt: title only, for messy artist metadata.
        if songs.isEmpty,
           let retryURL = makeURL(
            host: "mobileservice.kugou.com",
            path: "/api/v3/search/song",
            items: [
                .init(name: "format", value: "json"),
                .init(name: "keyword", value: name),
                .init(name: "page", value: "1"),
                .init(name: "pagesize", value: "5")
            ]
           ),
           let root = await rawJSON(retryURL) as? [String: Any],
           let data = root["data"] as? [String: Any],
           let info = data["info"] as? [[String: Any]] {
            songs = info
        }

        let ranked = songs.compactMap { candidate -> (song: [String: Any], score: Double)? in
            guard let hash = candidate["hash"] as? String else { return nil }
            let score = matchScore(
                title: candidate["songname"] as? String ?? "",
                artist: candidate["singername"] as? String ?? "",
                duration: (candidate["duration"] as? NSNumber)?.doubleValue ?? 0,
                wantedTitle: name,
                wantedArtist: artist,
                wantedDuration: 0
            )
            return (candidate, score)
        }
        .sorted { $0.score > $1.score }

        guard let best = ranked.first, best.score >= matchThreshold,
              let hash = best.song["hash"] as? String,
              let durationSeconds = (best.song["duration"] as? NSNumber)?.intValue,
              durationSeconds > 0
        else { return (nil, songs.isEmpty ? "nosong" : "lowmatch") }

        let song = best.song

        let songName = song["songname"] as? String ?? name
        let singer = song["singername"] as? String ?? artist

        guard let candidateURL = makeURL(
            host: "lyrics.kugou.com",
            path: "/search",
            items: [
                .init(name: "ver", value: "1"),
                .init(name: "man", value: "yes"),
                .init(name: "client", value: "pc"),
                .init(name: "keyword", value: "\(songName) \(singer)"),
                .init(name: "duration", value: String(durationSeconds * 1000)),
                .init(name: "hash", value: hash)
            ]
        ) else { return (nil, "nourl") }

        guard let candidateRoot = await rawJSON(candidateURL) as? [String: Any],
              let candidates = candidateRoot["candidates"] as? [[String: Any]],
              !candidates.isEmpty
        else { return (nil, "nocand") }

        for candidate in candidates.prefix(3) {
            guard let id = stringValue(candidate["id"]),
                  let accesskey = candidate["accesskey"] as? String,
                  let downloadURL = makeURL(
                    host: "lyrics.kugou.com",
                    path: "/download",
                    items: [
                        .init(name: "ver", value: "1"),
                        .init(name: "client", value: "pc"),
                        .init(name: "id", value: id),
                        .init(name: "accesskey", value: accesskey),
                        .init(name: "fmt", value: "lrc"),
                        .init(name: "charset", value: "utf8")
                    ]
                  )
            else { continue }

            guard let downloadRoot = await rawJSON(downloadURL) as? [String: Any],
                  let encoded = downloadRoot["content"] as? String,
                  let data = Data(base64Encoded: encoded),
                  let lrc = String(data: data, encoding: .utf8)
            else { continue }

            let parsed = parse(lrc)
            if !parsed.isEmpty {
                print("[Lyrics] kugou supplied \(parsed.count) synced lines")
                return (parsed, "ok")
            }
        }

        return (nil, "nodl")
    }

    /// textyl: [{ "seconds": 12, "lyrics": "…" }] — real timings, smaller catalogue.
    private static func textylLyrics(name: String, artist: String) async -> [Line]? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.textyl.co"
        components.path = "/api/lyrics"
        components.queryItems = [.init(name: "q", value: "\(artist) \(name)".trimmingCharacters(in: .whitespaces))]

        guard let url = components.url else { return nil }

        let result: ([TextylLine]?, String?) = await get(url: url)
        guard let payloads = result.0, !payloads.isEmpty else { return nil }

        let lines = payloads
            .filter { !$0.lyrics.trimmingCharacters(in: .whitespaces).isEmpty }
            .sorted { $0.seconds < $1.seconds }
            .enumerated()
            .map { Line(id: $0.offset, text: $0.element.lyrics.trimmingCharacters(in: .whitespaces), startTime: $0.element.seconds) }

        return lines.isEmpty ? nil : lines
    }

    private static func plainLyrics(name: String, artist: String) async -> ([Line]?, String) {
        guard !artist.isEmpty else { return (nil, "noartist") }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.lyrics.ovh"
        components.path = "/v1/\(artist)/\(name)"

        guard let url = components.url else { return (nil, "nourl") }

        let result: (OVHLyrics?, String?) = await get(url: url)
        guard let payload = result.0 else { return (nil, "miss") }

        let lines = payload.lyrics
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { line in
                !line.isEmpty
                    && !line.hasPrefix("Paroles de la chanson")
                    && !line.contains("***")
            }
            .enumerated()
            .map { Line(id: $0.offset, text: $0.element, startTime: nil) }

        return (lines.isEmpty ? nil : lines, "ok")
    }

    /// Human-readable form of the usual networking failures, so the panel can
    /// show something better than "didn't load".
    private static func describe(_ error: Error) -> String {
        let nsError = error as NSError
        switch nsError.code {
        case NSURLErrorNotConnectedToInternet:
            return "No internet connection"
        case NSURLErrorTimedOut:
            return "The lyrics service timed out"
        case NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost:
            return "Cannot reach the lyrics service"
        case NSURLErrorAppTransportSecurityRequiresSecureConnection:
            return "Blocked by App Transport Security"
        default:
            return "\(nsError.localizedDescription)"
        }
    }

    // MARK: Parsing

    private static func lines(from payload: Payload) -> [Line]? {
        if let synced = payload.syncedLyrics, !synced.isEmpty {
            let parsed = parse(synced)
            if !parsed.isEmpty { return parsed }
        }
        if let plain = payload.plainLyrics, !plain.isEmpty {
            let parsed = plain
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .enumerated()
                .map { Line(id: $0.offset, text: $0.element, startTime: nil) }
            if !parsed.isEmpty { return parsed }
        }
        return nil
    }

    private static func parse(_ lrc: String) -> [Line] {
        var result: [Line] = []

        for raw in lrc.split(separator: "\n", omittingEmptySubsequences: true) {
            var rest = raw[...]
            var times: [TimeInterval] = []

            while rest.first == "[" {
                guard let close = rest.firstIndex(of: "]") else { break }
                let inside = rest[rest.index(after: rest.startIndex)..<close]
                guard let time = timestamp(String(inside)) else { break }
                times.append(time)
                rest = rest[rest.index(after: close)...]
            }

            let content = rest.trimmingCharacters(in: .whitespaces)
            guard !times.isEmpty, !content.isEmpty else { continue }

            for time in times {
                result.append(Line(id: result.count, text: content, startTime: time))
            }
        }

        result.sort { ($0.startTime ?? 0) < ($1.startTime ?? 0) }
        return result.enumerated().map {
            Line(id: $0.offset, text: $0.element.text, startTime: $0.element.startTime)
        }
    }

    /// "00:12.34" / "00:12" / "01:02:03.45" → seconds.
    private static func timestamp(_ text: String) -> TimeInterval? {
        let parts = text.split(separator: ":")
        guard parts.count == 2 || parts.count == 3 else { return nil }

        var total: TimeInterval = 0
        for (index, part) in parts.enumerated() {
            let isLast = index == parts.count - 1
            let value: Double

            if isLast {
                guard let seconds = Double(part.replacingOccurrences(of: ",", with: ".")) else { return nil }
                value = seconds
            } else {
                guard let whole = Double(part) else { return nil }
                value = whole
            }

            total = total * 60 + value
        }
        return total
    }
}
