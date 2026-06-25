import SwiftUI

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

    var bestAudioFormat: AudioFormat? {
        providerMappings?.compactMap(\.audioFormat).max { a, b in
            let scoreA = a.qualityScore
            let scoreB = b.qualityScore
            if scoreA != scoreB { return scoreA < scoreB }
            return (a.bitRate ?? 0) < (b.bitRate ?? 0)
        }
    }

    var qualityBadge: QualityBadge? {
        guard let fmt = bestAudioFormat else { return nil }
        let isHiRes = (fmt.sampleRate ?? 0) >= 96000 || (fmt.bitDepth ?? 0) >= 24
        let isLossless: Bool = {
            guard let ct = fmt.contentType else { return false }
            switch ct.lowercased() {
            case "flac", "alac", "wav", "aiff", "dsf", "dff", "ape", "wmal", "pcm": return true
            default: return false
            }
        }()
        let detailsHiRes = providerMappings?.contains { $0.details?.lowercased() == "hi-res" } ?? false
        if isHiRes || detailsHiRes {
            let sr = fmt.sampleRate ?? 0
            let bd = fmt.bitDepth ?? 0
            if sr >= 192000 && bd >= 24 { return .hiResMaster }
            return .hiRes
        }
        if isLossless { return .lossless }
        return nil
    }

    enum QualityBadge: String {
        case hiResMaster = "超清母带"
        case hiRes = "Hi-Res"
        case lossless = "无损"

        var label: String { rawValue }

        var color: Color {
            switch self {
            case .hiResMaster: return Color(red: 0.85, green: 0.65, blue: 0.13)
            case .hiRes: return Color(red: 0.85, green: 0.65, blue: 0.13)
            case .lossless: return Color(red: 0.0, green: 0.58, blue: 1.0)
            }
        }
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

struct AudioFormat: Codable, Hashable {
    let contentType: String?
    let codecType: String?
    let sampleRate: Int?
    let bitDepth: Int?
    let channels: Int?
    let bitRate: Int?

    var qualityScore: Int {
        var score = 0
        if let ct = contentType, ct.lowercased() == "flac" { score += 100 }
        if let sr = sampleRate {
            if sr >= 192000 { score += 300 }
            else if sr >= 96000 { score += 200 }
            else if sr >= 48000 { score += 100 }
        }
        if let bd = bitDepth {
            if bd >= 24 { score += 200 }
            else if bd >= 16 { score += 100 }
        }
        return score
    }

    enum CodingKeys: String, CodingKey {
        case contentType = "content_type"
        case codecType = "codec_type"
        case sampleRate = "sample_rate"
        case bitDepth = "bit_depth"
        case channels
        case bitRate = "bit_rate"
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
    let audioFormat: AudioFormat?
    let details: String?

    enum CodingKeys: String, CodingKey {
        case itemId = "item_id"
        case providerDomain = "provider_domain"
        case providerInstance = "provider_instance"
        case audioFormat = "audio_format"
        case details
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
