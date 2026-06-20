import Foundation

struct Podcast: Identifiable, Codable, Hashable {
    let itemId: String
    let provider: String
    let name: String
    let uri: String
    let metadata: MediaItemMetadata?
    let totalEpisodes: Int?
    var favorite: Bool?

    var id: String { itemId }
    var imageUrl: String? {
        metadata?.images?.first(where: { $0.type == "thumb" })?.path ??
        metadata?.images?.first?.path
    }

    enum CodingKeys: String, CodingKey {
        case itemId = "item_id"
        case provider, name, uri, metadata
        case totalEpisodes = "total_episodes"
    }
}

struct Episode: Identifiable, Codable, Hashable {
    let itemId: String
    let provider: String
    let name: String
    let description: String?
    let duration: TimeInterval?
    let uri: String
    let metadata: MediaItemMetadata?
    let releaseDate: String?
    let podcastName: String?
    var favorite: Bool?

    var id: String { itemId }
    var imageUrl: String? {
        metadata?.images?.first(where: { $0.type == "thumb" })?.path ??
        metadata?.images?.first?.path
    }

    var formattedDuration: String {
        guard let duration = duration else { return "--:--" }
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    enum CodingKeys: String, CodingKey {
        case itemId = "item_id"
        case provider, name, description, duration, uri, metadata
        case releaseDate = "release_date"
        case podcastName = "podcast_name"
    }
}
