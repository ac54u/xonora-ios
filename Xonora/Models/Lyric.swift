import Foundation

struct Lyric: Identifiable, Codable, Hashable {
    let lineId: String?
    let start: TimeInterval?
    let end: TimeInterval?
    let text: String
    let id: String

    init(lineId: String? = nil, start: TimeInterval? = nil, end: TimeInterval? = nil, text: String) {
        self.lineId = lineId
        self.start = start
        self.end = end
        self.text = text
        self.id = lineId ?? UUID().uuidString
    }
}

struct LyricsResponse: Codable {
    let lyrics: [Lyric]?
    let hasSynced: Bool

    enum CodingKeys: String, CodingKey {
        case lyrics
        case hasSynced = "has_synced"
    }
}
