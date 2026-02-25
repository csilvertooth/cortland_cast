import Foundation
import Vapor

// MARK: - MusicKit Status

public struct MusicKitStatus: Content {
    let authorized: Bool
    let authorizationStatus: String
    let subscriptionActive: Bool
    let canPlayCatalog: Bool

    enum CodingKeys: String, CodingKey {
        case authorized
        case authorizationStatus = "authorization_status"
        case subscriptionActive = "subscription_active"
        case canPlayCatalog = "can_play_catalog"
    }
}

// MARK: - Search Response

public struct CatalogSearchResponse: Content {
    let songs: [CatalogSong]
    let albums: [CatalogAlbum]
    let artists: [CatalogArtist]
    let playlists: [CatalogPlaylistSummary]
}

// MARK: - Catalog Items

public struct CatalogSong: Content {
    let id: String
    let title: String
    let artist: String
    let album: String
    let artworkUrl: String?
    let duration: TimeInterval
    let storeUrl: String?
    var trackNumber: Int?

    enum CodingKeys: String, CodingKey {
        case id, title, artist, album, duration
        case artworkUrl = "artwork_url"
        case storeUrl = "store_url"
        case trackNumber = "track_number"
    }
}

public struct CatalogAlbum: Content {
    let id: String
    let title: String
    let artist: String
    let artworkUrl: String?
    let trackCount: Int
    let storeUrl: String?

    enum CodingKeys: String, CodingKey {
        case id, title, artist
        case artworkUrl = "artwork_url"
        case trackCount = "track_count"
        case storeUrl = "store_url"
    }
}

public struct CatalogArtist: Content {
    let id: String
    let name: String
    let artworkUrl: String?
    let storeUrl: String?

    enum CodingKeys: String, CodingKey {
        case id, name
        case artworkUrl = "artwork_url"
        case storeUrl = "store_url"
    }
}

public struct CatalogPlaylistSummary: Content {
    let id: String
    let name: String
    let description: String?
    let artworkUrl: String?
    let curatorName: String?
    let storeUrl: String?

    enum CodingKeys: String, CodingKey {
        case id, name, description
        case artworkUrl = "artwork_url"
        case curatorName = "curator_name"
        case storeUrl = "store_url"
    }
}

// MARK: - Detail Responses (with tracks)

public struct CatalogAlbumDetail: Content {
    let id: String
    let title: String
    let artist: String
    let artworkUrl: String?
    let trackCount: Int
    let storeUrl: String?
    let tracks: [CatalogSong]

    enum CodingKeys: String, CodingKey {
        case id, title, artist, tracks
        case artworkUrl = "artwork_url"
        case trackCount = "track_count"
        case storeUrl = "store_url"
    }
}

public struct CatalogPlaylistDetail: Content {
    let id: String
    let name: String
    let description: String?
    let artworkUrl: String?
    let curatorName: String?
    let storeUrl: String?
    let tracks: [CatalogSong]

    enum CodingKeys: String, CodingKey {
        case id, name, description, tracks
        case artworkUrl = "artwork_url"
        case curatorName = "curator_name"
        case storeUrl = "store_url"
    }
}

public struct CatalogArtistDetail: Content {
    let id: String
    let name: String
    let artworkUrl: String?
    let storeUrl: String?
    let topSongs: [CatalogSong]
    let albums: [CatalogAlbum]

    enum CodingKeys: String, CodingKey {
        case id, name, albums
        case artworkUrl = "artwork_url"
        case storeUrl = "store_url"
        case topSongs = "top_songs"
    }
}

// MARK: - Charts

public struct CatalogChartsResponse: Content {
    let songs: [CatalogSong]
    let albums: [CatalogAlbum]
    let playlists: [CatalogPlaylistSummary]
}

// MARK: - Recommendations

public struct CatalogRecommendationGroup: Content {
    let title: String
    let albums: [CatalogAlbum]
    let playlists: [CatalogPlaylistSummary]
}
