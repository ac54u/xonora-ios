import Foundation

struct MAPlayer: Identifiable, Codable, Hashable {
    let playerId: String
    let provider: String
    let name: String
    let type: String
    let available: Bool
    let state: PlayerState?
    let volume: Int?
    let volumeMuted: Bool?
    let currentMedia: CurrentMedia?
    var queueId: String?

    var id: String { playerId }

    enum CodingKeys: String, CodingKey {
        case playerId = "player_id"
        case provider
        case name
        case type
        case available
        case state
        case volume = "volume_level"
        case volumeMuted = "volume_muted"
        case currentMedia = "current_media"
        case queueId = "active_source"
    }
}

enum PlayerState: String, Codable {
    case idle = "idle"
    case playing = "playing"
    case paused = "paused"
    case off = "off"
    case unknown

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = PlayerState(rawValue: rawValue) ?? .unknown
    }
}

struct CurrentMedia: Codable, Hashable {
    let title: String?
    let artist: String?
    let album: String?
    let imageUrl: String?
    let duration: TimeInterval?
    let position: TimeInterval?
    let uri: String?

    enum CodingKeys: String, CodingKey {
        case title
        case artist
        case album
        case imageUrl = "image_url"
        case duration
        case position
        case uri
    }
}

struct QueueItem: Identifiable, Codable, Hashable {
    let queueItemId: String
    let name: String
    let artist: String?
    let album: String?
    let imageUrl: String?
    let duration: TimeInterval?
    let uri: String?

    var id: String { queueItemId }

    enum CodingKeys: String, CodingKey {
        case queueItemId = "queue_item_id"
        case name
        case artist
        case album
        case imageUrl = "image"
        case duration
        case uri
        case mediaItem = "media_item"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        queueItemId = try c.decode(String.self, forKey: .queueItemId)
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        artist = try? c.decode(String.self, forKey: .artist)
        album = try? c.decode(String.self, forKey: .album)
        imageUrl = try? c.decode(String.self, forKey: .imageUrl)
        duration = try? c.decode(TimeInterval.self, forKey: .duration)
        // The server often omits a top-level `uri` and only exposes it inside the
        // nested media_item. Reorder/move relied on URI matching, so fall back to
        // the media_item's uri — otherwise the match failed and reorders were lost.
        if let topURI = try? c.decode(String.self, forKey: .uri) {
            uri = topURI
        } else if let media = try? c.decode([String: MAJSONValue].self, forKey: .mediaItem),
                  case let .string(mediaURI)? = media["uri"] {
            uri = mediaURI
        } else {
            uri = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(queueItemId, forKey: .queueItemId)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(artist, forKey: .artist)
        try c.encodeIfPresent(album, forKey: .album)
        try c.encodeIfPresent(imageUrl, forKey: .imageUrl)
        try c.encodeIfPresent(duration, forKey: .duration)
        try c.encodeIfPresent(uri, forKey: .uri)
    }
}

/// Minimal JSON value used to dig a single string field out of a heterogeneous
/// nested object (e.g. media_item.uri) without decoding the whole structure.
enum MAJSONValue: Codable {
    case string(String)
    case other

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let s = try? container.decode(String.self) {
            self = .string(s)
        } else {
            self = .other
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s): try container.encode(s)
        case .other: try container.encodeNil()
        }
    }
}
