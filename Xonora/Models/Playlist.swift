import Foundation

struct Playlist: Identifiable, Codable, Hashable {
    let itemId: String
    let provider: String
    let name: String
    let uri: String
    let metadata: MediaItemMetadata?
    let isEditable: Bool?
    var favorite: Bool?

    var id: String { itemId }

    var imageUrl: String? { metadata?.thumbnailImageUrl }

    enum CodingKeys: String, CodingKey {
        case itemId = "item_id"
        case provider
        case name
        case uri
        case metadata
        case isEditable = "is_editable"
    }
}
