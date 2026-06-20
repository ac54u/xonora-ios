import Foundation

struct Lyric: Identifiable, Codable, Hashable {
    let lineId: String?
    let start: TimeInterval?
    let end: TimeInterval?
    let text: String

    var id: String { lineId ?? UUID().uuidString }
}

struct LyricsResponse: Codable {
    let lyrics: [Lyric]?
    let hasSynced: Bool

    enum CodingKeys: String, CodingKey {
        case lyrics
        case hasSynced = "has_synced"
    }
}
