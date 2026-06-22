import Foundation

struct Track: Identifiable, Codable, Hashable {
    let itemId: String
    let provider: String
    let name: String
    let version: String?
    let duration: TimeInterval?
    let trackNumber: Int?
    let discNumber: Int?
    let uri: String
    let artists: [ArtistReference]?
    let album: AlbumReference?
    let metadata: MediaItemMetadata?
    let providerMappings: [ProviderMapping]?
    var favorite: Bool?

    var id: String { itemId }

    var artistNames: String {
        artists?.map { $0.name }.joined(separator: ", ") ?? "Unknown Artist"
    }

    var imageUrl: String? { metadata?.thumbnailImageUrl }

    var formattedDuration: String {
        guard let duration = duration, duration >= 0 else { return "--:--" }
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    enum CodingKeys: String, CodingKey {
        case itemId = "item_id"
        case provider
        case name
        case version
        case duration
        case trackNumber = "track_number"
        case discNumber = "disc_number"
        case uri
        case artists
        case album
        case metadata
        case providerMappings = "provider_mappings"
    }
}

struct MediaItemMetadata: Codable, Hashable {
    let images: [MediaItemImage]?
}

struct MediaItemImage: Codable, Hashable {
    let type: String
    let path: String
    let provider: String
    let proxyId: String?

    enum CodingKeys: String, CodingKey {
        case type, path, provider
        case proxyId = "proxy_id"
    }
}

extension MediaItemMetadata {
    var thumbnailImageUrl: String? {
        let img = images?.first(where: { $0.type == "thumb" }) ?? images?.first
        return img?.proxyId ?? img?.path
    }
}

struct ProviderMapping: Codable, Hashable {
    let itemId: String
    let providerDomain: String
    let providerInstance: String

    enum CodingKeys: String, CodingKey {
        case itemId = "item_id"
        case providerDomain = "provider_domain"
        case providerInstance = "provider_instance"
    }
}

struct ArtistReference: Codable, Hashable {
    let itemId: String?
    let provider: String?
    let name: String

    enum CodingKeys: String, CodingKey {
        case itemId = "item_id"
        case provider
        case name
    }
}

struct AlbumReference: Codable, Hashable {
    let itemId: String
    let provider: String
    let name: String
    let metadata: MediaItemMetadata?
    
    var imageUrl: String? { metadata?.thumbnailImageUrl }

    enum CodingKeys: String, CodingKey {
        case itemId = "item_id"
        case provider
        case name
        case metadata
    }
}
