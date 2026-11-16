
//
//  AppleMusicMotionService.swift
//  DynamicNotch
//
//  Resolves Apple Music animated album artwork through Apple's AMP API.
//
//  Flow:
//  1. Search iTunes for the playing track.
//  2. Resolve the album collection ID.
//  3. Fetch Apple's public web-player bearer token.
//  4. Request the album with extend=editorialVideo.
//  5. Extract motionDetailSquare.video (HLS).
//  6. Return the actual video URL, NOT the preview image.
//
//  No Apple Music subscription or user sign-in required.
//  Uses Apple's undocumented web-player API.
//

import Foundation

actor AppleMusicMotionService {

    static let shared = AppleMusicMotionService()

    struct MotionArt: Sendable {
        let videoURL: URL?
        let previewURL: URL?
        let status: String

        static let none = MotionArt(
            videoURL: nil,
            previewURL: nil,
            status: "none"
        )
    }

    private struct TrackMatch {
        let albumID: Int
        let storefront: String
    }

    private struct SearchResponse: Decodable {
        struct Result: Decodable {
            let trackName: String?
            let artistName: String?
            let collectionId: Int?
        }

        let results: [Result]
    }

    private var storefront: String {
        if let override = UserDefaults.standard.string(
            forKey: "AppleMusicStorefront"
        ), override.count == 2 {
            return override.lowercased()
        }

        return (
            Locale.current.region?.identifier ?? "US"
        ).lowercased()
    }

    private var cache: [String: MotionArt] = [:]
    private var albumCache: [String: MotionArt] = [:]
    private var inFlight: [String: Task<MotionArt, Never>] = [:]

    private var cachedToken: String?
    private var didLogMissingMotion = false

    private static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " +
        "AppleWebKit/605.1.15 (KHTML, like Gecko) " +
        "Version/17.0 Safari/605.1.15"

    // MARK: - Public

    func motionArt(
        title: String,
        artist: String,
        cacheKey: String
    ) async -> MotionArt {

        if let cached = cache[cacheKey] {
            return cached
        }

        if let existing = inFlight[cacheKey] {
            return await existing.value
        }

        let task = Task<MotionArt, Never> {
            [weak self] in

            guard let self else {
                return MotionArt.none
            }

            return await self.resolve(
                title: title,
                artist: artist
            )
        }

        inFlight[cacheKey] = task

        let result = await task.value

        cache[cacheKey] = result
        inFlight[cacheKey] = nil

        return result
    }

    func verify() async -> String {
        reset()

        let result = await resolve(
            title: "Blinding Lights",
            artist: "The Weeknd"
        )

        print("[Motion] Verification: \(result.status)")
        print("[Motion] Video: \(result.videoURL?.absoluteString ?? "nil")")

        return result.videoURL != nil ? "ok" : result.status
    }

    func reset() {
        cache.removeAll()
        albumCache.removeAll()
        inFlight.removeAll()
        cachedToken = nil
        didLogMissingMotion = false
    }

    // MARK: - Resolution

    private func resolve(
        title: String,
        artist: String
    ) async -> MotionArt {

        guard !title.isEmpty else {
            return .none
        }

        guard let match = await search(
            title: title,
            artist: artist
        ) else {
            return MotionArt(
                videoURL: nil,
                previewURL: nil,
                status: "no-match"
            )
        }

        return await albumMotion(
            collectionID: match.albumID,
            storefront: match.storefront
        )
    }

    // MARK: - iTunes Search

    private func search(
        title: String,
        artist: String
    ) async -> TrackMatch? {

        let country = storefront

        guard var components = URLComponents(
            string: "https://itunes.apple.com/search"
        ) else {
            return nil
        }

        components.queryItems = [
            URLQueryItem(
                name: "term",
                value: "\(title) \(artist)"
            ),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "20"),
            URLQueryItem(
                name: "country",
                value: country.uppercased()
            )
        ]

        guard let url = components.url else {
            return nil
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15

        do {
            let (data, response) =
                try await URLSession.shared.data(for: request)

            guard (response as? HTTPURLResponse)?.statusCode == 200
            else {
                print("[Motion] iTunes search failed")
                return nil
            }

            let decoded = try JSONDecoder().decode(
                SearchResponse.self,
                from: data
            )

            let wantedTitle = normalize(title)
            let wantedArtist = normalize(artist)

            let best = decoded.results.compactMap {
                item -> (TrackMatch, Int)? in

                guard
                    let albumID = item.collectionId,
                    let name = item.trackName
                else {
                    return nil
                }

                let itemTitle = normalize(name)
                let itemArtist = normalize(item.artistName ?? "")

                var score = 0

                if itemTitle == wantedTitle {
                    score += 60
                } else if itemTitle.contains(wantedTitle) ||
                            wantedTitle.contains(itemTitle) {
                    score += 35
                }

                if !wantedArtist.isEmpty {
                    if itemArtist == wantedArtist {
                        score += 40
                    } else if itemArtist.contains(wantedArtist) ||
                                wantedArtist.contains(itemArtist) {
                        score += 25
                    }
                }

                guard score >= 55 else {
                    return nil
                }

                return (
                    TrackMatch(
                        albumID: albumID,
                        storefront: country
                    ),
                    score
                )
            }
            .max { $0.1 < $1.1 }

            if let best {
                print("[Motion] Matched album: \(best.0.albumID)")
            }

            return best?.0

        } catch {
            print("[Motion] Search error: \(error)")
            return nil
        }
    }

    // MARK: - Apple Music Web Token

    private func getToken(forceRefresh: Bool = false) async -> String? {

        if !forceRefresh, let cachedToken {
            return cachedToken
        }

        do {
            // Fetch Apple Music's web player homepage.

            guard let homepageURL = URL(
                string: "https://music.apple.com/"
            ) else {
                return nil
            }

            var homepageRequest = URLRequest(url: homepageURL)
            homepageRequest.timeoutInterval = 20
            homepageRequest.setValue(
                Self.userAgent,
                forHTTPHeaderField: "User-Agent"
            )

            let (homepageData, homepageResponse) =
                try await URLSession.shared.data(
                    for: homepageRequest
                )

            guard
                (homepageResponse as? HTTPURLResponse)?.statusCode == 200,
                let homepage = String(
                    data: homepageData,
                    encoding: .utf8
                )
            else {
                print("[Motion] Could not fetch Apple homepage")
                return nil
            }

            // Find the JavaScript bundle containing the web token.

            let patterns = [
                #"/assets/index~[^/"']+\.js"#,
                #"/assets/index-legacy-[^/"']+\.js"#,
                #"/assets/index-legacy~[^/"']+\.js"#
            ]

            var scriptPaths: [String] = []

            for pattern in patterns {
                guard let regex = try? NSRegularExpression(
                    pattern: pattern
                ) else {
                    continue
                }

                let range = NSRange(
                    homepage.startIndex..<homepage.endIndex,
                    in: homepage
                )

                let matches = regex.matches(
                    in: homepage,
                    range: range
                )

                for match in matches {
                    if let range = Range(
                        match.range,
                        in: homepage
                    ) {
                        let path = String(homepage[range])

                        if !scriptPaths.contains(path) {
                            scriptPaths.append(path)
                        }
                    }
                }
            }

            guard !scriptPaths.isEmpty else {
                print("[Motion] No Apple JS bundle found")
                return nil
            }

            // Download the bundle and extract its JWT.

            let tokenPattern =
                #"eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+"#

            for path in scriptPaths {
                guard let scriptURL = URL(
                    string: "https://music.apple.com" + path
                ) else {
                    continue
                }

                var scriptRequest = URLRequest(url: scriptURL)
                scriptRequest.timeoutInterval = 25
                scriptRequest.setValue(
                    Self.userAgent,
                    forHTTPHeaderField: "User-Agent"
                )

                let (scriptData, scriptResponse) =
                    try await URLSession.shared.data(
                        for: scriptRequest
                    )

                guard
                    (scriptResponse as? HTTPURLResponse)?.statusCode == 200,
                    let script = String(
                        data: scriptData,
                        encoding: .utf8
                    )
                else {
                    continue
                }

                guard let regex = try? NSRegularExpression(
                    pattern: tokenPattern
                ) else {
                    continue
                }

                let range = NSRange(
                    script.startIndex..<script.endIndex,
                    in: script
                )

                if let match = regex.firstMatch(
                    in: script,
                    range: range
                ), let tokenRange = Range(
                    match.range,
                    in: script
                ) {

                    let token = String(script[tokenRange])

                    cachedToken = token

                    print("[Motion] Apple bearer token acquired")
                    return token
                }
            }

            print("[Motion] Could not extract Apple bearer token")
            return nil

        } catch {
            print("[Motion] Token error: \(error)")
            return nil
        }
    }

    // MARK: - AMP Catalog API

    private func albumMotion(
        collectionID: Int,
        storefront: String
    ) async -> MotionArt {

        let albumKey = "\(storefront):\(collectionID)"

        if let cached = albumCache[albumKey] {
            return cached
        }

        guard let token = await getToken() else {
            return MotionArt(
                videoURL: nil,
                previewURL: nil,
                status: "token:error"
            )
        }

        let result = await fetchAlbumMotion(
            collectionID: collectionID,
            storefront: storefront,
            token: token
        )

        // A 401/403 may indicate an expired web-player token.
        // Refresh it once and retry.

        if result.status == "http:401" ||
            result.status == "http:403" {

            print("[Motion] Token rejected. Refreshing...")

            guard let refreshedToken = await getToken(
                forceRefresh: true
            ) else {
                return result
            }

            let retry = await fetchAlbumMotion(
                collectionID: collectionID,
                storefront: storefront,
                token: refreshedToken
            )

            if retry.videoURL != nil {
                albumCache[albumKey] = retry
            }

            return retry
        }

        // Only cache successful motion results and confirmed misses.
        // Do not permanently cache temporary network/API failures.

        if result.status == "ok" ||
            result.status == "no-motion" {
            albumCache[albumKey] = result
        }

        return result
    }

    private func fetchAlbumMotion(
        collectionID: Int,
        storefront: String,
        token: String
    ) async -> MotionArt {

        let endpoint =
            "https://amp-api.music.apple.com/v1/catalog/" +
            "\(storefront)/albums/\(collectionID)"

        guard var components = URLComponents(
            string: endpoint
        ) else {
            return MotionArt(
                videoURL: nil,
                previewURL: nil,
                status: "api:url"
            )
        }

        components.queryItems = [
            URLQueryItem(
                name: "extend",
                value: "editorialVideo"
            )
        ]

        guard let url = components.url else {
            return MotionArt(
                videoURL: nil,
                previewURL: nil,
                status: "api:url"
            )
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20

        request.setValue(
            "Bearer \(token)",
            forHTTPHeaderField: "Authorization"
        )

        request.setValue(
            Self.userAgent,
            forHTTPHeaderField: "User-Agent"
        )

        request.setValue(
            "https://music.apple.com",
            forHTTPHeaderField: "Origin"
        )

        request.setValue(
            "https://music.apple.com/",
            forHTTPHeaderField: "Referer"
        )

        request.setValue(
            "application/json",
            forHTTPHeaderField: "Accept"
        )

        do {
            let (data, response) =
                try await URLSession.shared.data(for: request)

            let status = (
                response as? HTTPURLResponse
            )?.statusCode ?? -1

            print(
                "[Motion] AMP album \(collectionID) -> \(status)"
            )

            guard status == 200 else {
                return MotionArt(
                    videoURL: nil,
                    previewURL: nil,
                    status: "http:\(status)"
                )
            }

            guard
                let json = try JSONSerialization.jsonObject(
                    with: data
                ) as? [String: Any],
                let dataArray = json["data"] as? [[String: Any]],
                let album = dataArray.first,
                let attributes = album["attributes"] as? [String: Any]
            else {
                print("[Motion] Invalid AMP JSON")
                return MotionArt(
                    videoURL: nil,
                    previewURL: nil,
                    status: "api:invalid-json"
                )
            }

            guard let editorialVideo = attributes[
                "editorialVideo"
            ] as? [String: Any] else {

                print("[Motion] No editorialVideo attribute")

                return MotionArt(
                    videoURL: nil,
                    previewURL: nil,
                    status: "no-motion"
                )
            }

            // Prefer square artwork for the DynamicNotch.

            let square = editorialVideo[
                "motionDetailSquare"
            ] as? [String: Any]

            // Fallback to Apple's alternate square format.

            let alternateSquare = editorialVideo[
                "motionSquareVideo1x1"
            ] as? [String: Any]

            let tall = editorialVideo[
                "motionDetailTall"
            ] as? [String: Any]

            // IMPORTANT:
            // "video" is the actual HLS video manifest.
            // "previewFrame.url" is only a static image.

            let selected = square ?? alternateSquare ?? tall

            guard
                let selected,
                let videoString = selected["video"] as? String,
                let videoURL = URL(string: videoString),
                videoURL.scheme == "https"
            else {

                if !didLogMissingMotion {
                    didLogMissingMotion = true

                    print(
                        "[Motion] Album \(collectionID) has no usable video"
                    )

                    print(
                        "[Motion] Available keys: " +
                        "\(editorialVideo.keys.sorted())"
                    )
                }

                return MotionArt(
                    videoURL: nil,
                    previewURL: nil,
                    status: "no-motion"
                )
            }

            var previewURL: URL?

            if let previewFrame = selected[
                "previewFrame"
            ] as? [String: Any],
               let previewString = previewFrame[
                   "url"
               ] as? String {

                let resolvedPreview = previewString
                    .replacingOccurrences(of: "{w}", with: "768")
                    .replacingOccurrences(of: "{h}", with: "768")
                    .replacingOccurrences(of: "{f}", with: "jpg")

                previewURL = URL(string: resolvedPreview)
            }

            print("[Motion] MOTION ART FOUND")
            print("[Motion] Video URL: \(videoURL)")
            print("[Motion] Preview URL: \(previewURL?.absoluteString ?? "none")")

            return MotionArt(
                videoURL: videoURL,
                previewURL: previewURL,
                status: "ok"
            )

        } catch {
            print("[Motion] AMP request error: \(error)")

            return MotionArt(
                videoURL: nil,
                previewURL: nil,
                status: "api:error"
            )
        }
    }

    // MARK: - Matching

    private func normalize(_ value: String) -> String {

        var text = value.lowercased()

        text = text.replacingOccurrences(
            of: #"\([^)]*\)"#,
            with: " ",
            options: .regularExpression
        )

        text = text.replacingOccurrences(
            of: #"\[[^\]]*\]"#,
            with: " ",
            options: .regularExpression
        )

        text = text.replacingOccurrences(
            of: #"\b(feat|ft|featuring)\.?\s.*$"#,
            with: " ",
            options: .regularExpression
        )

        text = text.replacingOccurrences(
            of: #"[^a-z0-9 ]"#,
            with: " ",
            options: .regularExpression
        )

        return text
            .split(separator: " ")
            .joined(separator: " ")
    }
}
