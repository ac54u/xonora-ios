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

    /// The Music Assistant "builtin" provider generates these system playlists with
    /// hardcoded English names regardless of the app's locale. Map the known ones to
    /// localized strings; everything else (user playlists) is shown verbatim.
    var displayName: String {
        switch name {
        case "All favorited tracks":
            return NSLocalizedString("All favorited tracks", comment: "Built-in playlist name")
        case "Infinite Mix (favorites)":
            return NSLocalizedString("Infinite Mix (favorites)", comment: "Built-in playlist name")
        case "Infinite Mix (library)":
            return NSLocalizedString("Infinite Mix (library)", comment: "Built-in playlist name")
        default:
            // "<N> Random tracks (from library)" — count varies.
            if name.range(of: #"^\d+ Random tracks \(from library\)$"#, options: .regularExpression) != nil {
                let count = name.prefix(while: { $0.isNumber })
                return String(format: NSLocalizedString("%@ Random tracks (from library)", comment: "Built-in playlist name"), String(count))
            }
            return name
        }
    }

    enum CodingKeys: String, CodingKey {
        case itemId = "item_id"
        case provider
        case name
        case uri
        case metadata
        case isEditable = "is_editable"
    }
}
