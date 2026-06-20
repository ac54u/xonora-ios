import Foundation

struct Album: Identifiable, Codable, Hashable {
    let itemId: String
    let provider: String
    let name: String
    let version: String?
    let year: Int?
    let artists: [ArtistReference]?
    let uri: String
    let metadata: MediaItemMetadata?
    var favorite: Bool?

    var id: String { itemId }

    var artistNames: String {
        artists?.map { $0.name }.joined(separator: ", ") ?? "Unknown Artist"
    }
    
    var imageUrl: String? { metadata?.thumbnailImageUrl }

    var displayYear: String {
        if let year = year {
            return String(year)
        }
        return ""
    }

    enum CodingKeys: String, CodingKey {
        case itemId = "item_id"
        case provider
        case name
        case version
        case year
        case artists
        case uri
        case metadata
    }
}

struct ImageInfo: Codable, Hashable {
    let url: String
    let type: String?
    let size: Int?
}
