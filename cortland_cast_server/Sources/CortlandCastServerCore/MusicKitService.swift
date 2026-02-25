import Foundation
import MusicKit

// Centralized MusicKit operations for Apple Music catalog access
public class MusicKitService {
    public static let shared = MusicKitService()

    // MARK: - Cache

    private var chartsCache: (data: CatalogChartsResponse, timestamp: Date)?
    private let chartsCacheTTL: TimeInterval = 30 * 60 // 30 minutes

    private var searchCache: [String: (data: CatalogSearchResponse, timestamp: Date)] = [:]
    private let searchCacheTTL: TimeInterval = 5 * 60 // 5 minutes
    private let maxSearchCacheEntries = 50

    private init() {}

    // MARK: - Authorization

    public var authorizationStatus: MusicAuthorization.Status {
        MusicAuthorization.currentStatus
    }

    public func requestAuthorization() async -> MusicAuthorization.Status {
        await MusicAuthorization.request()
    }

    public func checkSubscription() async -> Bool {
        do {
            let subscription = try await MusicSubscription.current
            return subscription.canPlayCatalogContent
        } catch {
            serverLog("MusicKit subscription check failed: \(error)", level: "ERROR")
            return false
        }
    }

    public func getStatus() async -> MusicKitStatus {
        let authorized = authorizationStatus == .authorized
        let canPlay = authorized ? await checkSubscription() : false
        return MusicKitStatus(
            authorized: authorized,
            authorizationStatus: String(describing: authorizationStatus),
            subscriptionActive: canPlay,
            canPlayCatalog: canPlay
        )
    }

    // MARK: - Catalog Search

    public func searchCatalog(term: String, types: Set<String>? = nil, limit: Int = 25) async throws -> CatalogSearchResponse {
        guard authorizationStatus == .authorized else {
            throw MusicKitServiceError.notAuthorized
        }

        // Check cache
        let cacheKey = "\(term.lowercased())|\(types?.sorted().joined(separator: ",") ?? "all")|\(limit)"
        if let cached = searchCache[cacheKey], Date().timeIntervalSince(cached.timestamp) < searchCacheTTL {
            return cached.data
        }

        let clampedLimit = min(max(limit, 1), 25)

        var request = MusicCatalogSearchRequest(term: term, types: [Song.self, Album.self, Artist.self, Playlist.self])
        request.limit = clampedLimit

        let response = try await request.response()

        let filterTypes = types ?? ["songs", "albums", "artists", "playlists"]

        let songs: [CatalogSong] = filterTypes.contains("songs") ? response.songs.map { song in
            CatalogSong(
                id: song.id.rawValue,
                title: song.title,
                artist: song.artistName,
                album: song.albumTitle ?? "",
                artworkUrl: song.artwork?.url(width: 300, height: 300)?.absoluteString,
                duration: song.duration ?? 0,
                storeUrl: song.url?.absoluteString
            )
        } : []

        let albums: [CatalogAlbum] = filterTypes.contains("albums") ? response.albums.map { album in
            CatalogAlbum(
                id: album.id.rawValue,
                title: album.title,
                artist: album.artistName,
                artworkUrl: album.artwork?.url(width: 300, height: 300)?.absoluteString,
                trackCount: album.trackCount,
                storeUrl: album.url?.absoluteString
            )
        } : []

        let artists: [CatalogArtist] = filterTypes.contains("artists") ? response.artists.map { artist in
            CatalogArtist(
                id: artist.id.rawValue,
                name: artist.name,
                artworkUrl: artist.artwork?.url(width: 300, height: 300)?.absoluteString,
                storeUrl: artist.url?.absoluteString
            )
        } : []

        let playlists: [CatalogPlaylistSummary] = filterTypes.contains("playlists") ? response.playlists.map { playlist in
            CatalogPlaylistSummary(
                id: playlist.id.rawValue,
                name: playlist.name,
                description: playlist.standardDescription,
                artworkUrl: playlist.artwork?.url(width: 300, height: 300)?.absoluteString,
                curatorName: playlist.curatorName,
                storeUrl: playlist.url?.absoluteString
            )
        } : []

        let result = CatalogSearchResponse(
            songs: songs,
            albums: albums,
            artists: artists,
            playlists: playlists
        )

        // Update cache (evict oldest if full)
        if searchCache.count >= maxSearchCacheEntries {
            if let oldestKey = searchCache.min(by: { $0.value.timestamp < $1.value.timestamp })?.key {
                searchCache.removeValue(forKey: oldestKey)
            }
        }
        searchCache[cacheKey] = (data: result, timestamp: Date())

        return result
    }

    // MARK: - Charts

    public func getCharts(limit: Int = 25) async throws -> CatalogChartsResponse {
        guard authorizationStatus == .authorized else {
            throw MusicKitServiceError.notAuthorized
        }

        // Check cache
        if let cached = chartsCache, Date().timeIntervalSince(cached.timestamp) < chartsCacheTTL {
            return cached.data
        }

        let clampedLimit = min(max(limit, 1), 25)

        var request = MusicCatalogChartsRequest(kinds: [.mostPlayed], types: [Song.self, Album.self, Playlist.self])
        request.limit = clampedLimit

        let response = try await request.response()

        let songs: [CatalogSong] = response.songCharts.flatMap { chart in
            chart.items.map { song in
                CatalogSong(
                    id: song.id.rawValue,
                    title: song.title,
                    artist: song.artistName,
                    album: song.albumTitle ?? "",
                    artworkUrl: song.artwork?.url(width: 300, height: 300)?.absoluteString,
                    duration: song.duration ?? 0,
                    storeUrl: song.url?.absoluteString
                )
            }
        }

        let albums: [CatalogAlbum] = response.albumCharts.flatMap { chart in
            chart.items.map { album in
                CatalogAlbum(
                    id: album.id.rawValue,
                    title: album.title,
                    artist: album.artistName,
                    artworkUrl: album.artwork?.url(width: 300, height: 300)?.absoluteString,
                    trackCount: album.trackCount,
                    storeUrl: album.url?.absoluteString
                )
            }
        }

        let playlists: [CatalogPlaylistSummary] = response.playlistCharts.flatMap { chart in
            chart.items.map { playlist in
                CatalogPlaylistSummary(
                    id: playlist.id.rawValue,
                    name: playlist.name,
                    description: playlist.standardDescription,
                    artworkUrl: playlist.artwork?.url(width: 300, height: 300)?.absoluteString,
                    curatorName: playlist.curatorName,
                    storeUrl: playlist.url?.absoluteString
                )
            }
        }

        let result = CatalogChartsResponse(songs: songs, albums: albums, playlists: playlists)

        // Update cache
        chartsCache = (data: result, timestamp: Date())

        return result
    }

    // MARK: - Catalog Browse

    public func getCatalogAlbum(id: String) async throws -> CatalogAlbumDetail {
        guard authorizationStatus == .authorized else {
            throw MusicKitServiceError.notAuthorized
        }

        let request = MusicCatalogResourceRequest<Album>(matching: \.id, equalTo: MusicItemID(id))
        let response = try await request.response()

        guard let album = response.items.first else {
            throw MusicKitServiceError.notFound("Album \(id) not found")
        }

        let detailedAlbum = try await album.with([.tracks])
        let tracks: [CatalogSong] = detailedAlbum.tracks?.map { track in
            CatalogSong(
                id: track.id.rawValue,
                title: track.title,
                artist: track.artistName,
                album: album.title,
                artworkUrl: track.artwork?.url(width: 300, height: 300)?.absoluteString,
                duration: track.duration ?? 0,
                storeUrl: track.url?.absoluteString,
                trackNumber: track.trackNumber
            )
        } ?? []

        return CatalogAlbumDetail(
            id: album.id.rawValue,
            title: album.title,
            artist: album.artistName,
            artworkUrl: album.artwork?.url(width: 300, height: 300)?.absoluteString,
            trackCount: album.trackCount,
            storeUrl: album.url?.absoluteString,
            tracks: tracks
        )
    }

    public func getCatalogPlaylist(id: String) async throws -> CatalogPlaylistDetail {
        guard authorizationStatus == .authorized else {
            throw MusicKitServiceError.notAuthorized
        }

        let request = MusicCatalogResourceRequest<Playlist>(matching: \.id, equalTo: MusicItemID(id))
        let response = try await request.response()

        guard let playlist = response.items.first else {
            throw MusicKitServiceError.notFound("Playlist \(id) not found")
        }

        let detailedPlaylist = try await playlist.with([.tracks])
        let tracks: [CatalogSong] = detailedPlaylist.tracks?.map { track in
            CatalogSong(
                id: track.id.rawValue,
                title: track.title,
                artist: track.artistName,
                album: track.albumTitle ?? "",
                artworkUrl: track.artwork?.url(width: 300, height: 300)?.absoluteString,
                duration: track.duration ?? 0,
                storeUrl: track.url?.absoluteString
            )
        } ?? []

        return CatalogPlaylistDetail(
            id: playlist.id.rawValue,
            name: playlist.name,
            description: playlist.standardDescription,
            artworkUrl: playlist.artwork?.url(width: 300, height: 300)?.absoluteString,
            curatorName: playlist.curatorName,
            storeUrl: playlist.url?.absoluteString,
            tracks: tracks
        )
    }

    public func getCatalogArtist(id: String) async throws -> CatalogArtistDetail {
        guard authorizationStatus == .authorized else {
            throw MusicKitServiceError.notAuthorized
        }

        let request = MusicCatalogResourceRequest<Artist>(matching: \.id, equalTo: MusicItemID(id))
        let response = try await request.response()

        guard let artist = response.items.first else {
            throw MusicKitServiceError.notFound("Artist \(id) not found")
        }

        let detailedArtist = try await artist.with([.topSongs, .albums])
        let topSongs: [CatalogSong] = detailedArtist.topSongs?.prefix(25).map { song in
            CatalogSong(
                id: song.id.rawValue,
                title: song.title,
                artist: song.artistName,
                album: song.albumTitle ?? "",
                artworkUrl: song.artwork?.url(width: 300, height: 300)?.absoluteString,
                duration: song.duration ?? 0,
                storeUrl: song.url?.absoluteString
            )
        } ?? []

        let albums: [CatalogAlbum] = detailedArtist.albums?.map { album in
            CatalogAlbum(
                id: album.id.rawValue,
                title: album.title,
                artist: album.artistName,
                artworkUrl: album.artwork?.url(width: 300, height: 300)?.absoluteString,
                trackCount: album.trackCount,
                storeUrl: album.url?.absoluteString
            )
        } ?? []

        return CatalogArtistDetail(
            id: artist.id.rawValue,
            name: artist.name,
            artworkUrl: artist.artwork?.url(width: 300, height: 300)?.absoluteString,
            storeUrl: artist.url?.absoluteString,
            topSongs: topSongs,
            albums: albums
        )
    }

    public func getRecommendations() async throws -> [CatalogRecommendationGroup] {
        guard authorizationStatus == .authorized else {
            throw MusicKitServiceError.notAuthorized
        }

        let request = MusicPersonalRecommendationsRequest()
        let response = try await request.response()

        return response.recommendations.prefix(10).compactMap { recommendation in
            let albums: [CatalogAlbum] = recommendation.albums.prefix(10).map { album in
                CatalogAlbum(
                    id: album.id.rawValue,
                    title: album.title,
                    artist: album.artistName,
                    artworkUrl: album.artwork?.url(width: 300, height: 300)?.absoluteString,
                    trackCount: album.trackCount,
                    storeUrl: album.url?.absoluteString
                )
            }

            let playlists: [CatalogPlaylistSummary] = recommendation.playlists.prefix(10).map { playlist in
                CatalogPlaylistSummary(
                    id: playlist.id.rawValue,
                    name: playlist.name,
                    description: playlist.standardDescription,
                    artworkUrl: playlist.artwork?.url(width: 300, height: 300)?.absoluteString,
                    curatorName: playlist.curatorName,
                    storeUrl: playlist.url?.absoluteString
                )
            }

            guard !albums.isEmpty || !playlists.isEmpty else { return nil }

            return CatalogRecommendationGroup(
                title: recommendation.title ?? "For You",
                albums: albums,
                playlists: playlists
            )
        }
    }

    // MARK: - Catalog Playback

    /// Play a catalog item by opening its Apple Music URL in Music.app.
    /// This preserves AirPlay routing since Music.app handles the stream.
    public func playCatalogItem(type: String, storeId: String) async -> AppleScriptResult {
        let urlPath: String
        switch type {
        case "catalog_song":
            urlPath = "song/\(storeId)"
        case "catalog_album":
            urlPath = "album/\(storeId)"
        case "catalog_playlist":
            urlPath = "playlist/\(storeId)"
        default:
            return AppleScriptResult(success: false, output: "", error: "Unknown catalog type: \(type)")
        }

        serverLog("Playing catalog item: type=\(type), storeId=\(storeId)", level: "INFO")

        // Use open location to play through Music.app (preserves AirPlay routing)
        let script = """
        tell application "Music"
            open location "https://music.apple.com/us/\(urlPath)"
            delay 1
            play
        end tell
        """

        return await runAppleScriptAsync(script)
    }

    /// Play a catalog item by its Apple Music store URL directly.
    public func playCatalogUrl(_ storeUrl: String) async -> AppleScriptResult {
        serverLog("Playing catalog URL: \(storeUrl)", level: "INFO")

        let escapedUrl = storeUrl.replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "Music"
            open location "\(escapedUrl)"
            delay 1
            play
        end tell
        """

        return await runAppleScriptAsync(script)
    }
}

// MARK: - Errors

public enum MusicKitServiceError: Error, CustomStringConvertible {
    case notAuthorized
    case noSubscription
    case notFound(String)
    case searchFailed(String)

    public var description: String {
        switch self {
        case .notAuthorized:
            return "MusicKit is not authorized. Please authorize Apple Music access."
        case .noSubscription:
            return "No active Apple Music subscription found."
        case .notFound(let detail):
            return detail
        case .searchFailed(let detail):
            return "Search failed: \(detail)"
        }
    }
}
