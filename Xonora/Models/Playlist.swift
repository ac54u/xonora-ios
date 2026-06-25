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

    var icon: String {
        switch name {
        case "All favorited tracks":
            return "heart.fill"
        case "Infinite Mix (favorites)", "Infinite Mix (library)":
            return "infinity"
        case "Random Album (from library)":
            return "shuffle"
        case "Random Artist (from library)":
            return "person.2.shuffle"
        case "Recently added tracks":
            return "clock.badge.plus"
        case "Recently played tracks":
            return "clock.arrow.circlepath"
        default:
            if name.range(of: #"^\d+ Random tracks \(from library\)$"#, options: .regularExpression) != nil {
                return "dice"
            }
            return "music.note.list"
        }
    }

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
        case "Random Album (from library)":
            return NSLocalizedString("Random Album (from library)", comment: "Built-in playlist name")
        case "Random Artist (from library)":
            return NSLocalizedString("Random Artist (from library)", comment: "Built-in playlist name")
        case "Recently added tracks":
            return NSLocalizedString("Recently added tracks", comment: "Built-in playlist name")
        case "Recently played tracks":
            return NSLocalizedString("Recently played tracks", comment: "Built-in playlist name")
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
