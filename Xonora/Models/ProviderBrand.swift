import SwiftUI

enum ProviderBrand: String, CaseIterable {
    case spotify, qobuz, tidal, deezer, appleMusic = "apple_music"
    case youtube, soundcloud, bandcamp, plex, emby
    case jellyfin, subsonic, navidrome, filesystemLocal = "filesystem_local"
    case airplay, chromecast, dlna, sonos, squeezebox
    case sendspin, builtin, test, unknown

    init(provider: String) {
        self = ProviderBrand(rawValue: provider) ?? .unknown
    }

    var displayName: String {
        switch self {
        case .spotify: return "Spotify"
        case .qobuz: return "Qobuz"
        case .tidal: return "Tidal"
        case .deezer: return "Deezer"
        case .appleMusic: return "Apple Music"
        case .youtube: return "YouTube"
        case .soundcloud: return "SoundCloud"
        case .bandcamp: return "Bandcamp"
        case .plex: return "Plex"
        case .emby: return "Emby"
        case .jellyfin: return "Jellyfin"
        case .subsonic: return "Subsonic"
        case .navidrome: return "Navidrome"
        case .filesystemLocal: return "Local Files"
        case .airplay: return "AirPlay"
        case .chromecast: return "Chromecast"
        case .dlna: return "DLNA"
        case .sonos: return "Sonos"
        case .squeezebox: return "Squeezebox"
        case .sendspin: return "Sendspin"
        case .builtin: return "Built-in"
        case .test: return "Test"
        case .unknown: return "Unknown"
        }
    }

    var icon: String {
        switch self {
        case .spotify: return "sparkles"
        case .qobuz: return "hifispeaker"
        case .tidal: return "waveform"
        case .deezer: return "music.note"
        case .appleMusic: return "apple.logo"
        case .youtube: return "play.rectangle"
        case .soundcloud: return "cloud"
        case .bandcamp: return "circle"
        case .plex: return "play"
        case .emby, .jellyfin: return "play.tv"
        case .subsonic, .navidrome: return "antenna.radiowaves.left.and.right"
        case .filesystemLocal: return "internaldrive"
        case .airplay: return "airplayaudio"
        case .chromecast: return "display"
        case .dlna: return "tv"
        case .sonos: return "hifispeaker.fill"
        case .squeezebox: return "rectangle.3.group"
        case .sendspin: return "iphone"
        case .builtin: return "speaker"
        case .test: return "wrench"
        case .unknown: return "questionmark"
        }
    }

    var color: Color {
        switch self {
        case .spotify: return Color(red: 0.11, green: 0.73, blue: 0.33)
        case .qobuz: return Color(red: 0.82, green: 0.17, blue: 0.22)
        case .tidal: return Color(red: 0.07, green: 0.07, blue: 0.07)
        case .deezer: return Color(red: 0.0, green: 0.0, blue: 0.0)
        case .appleMusic: return Color(red: 0.98, green: 0.18, blue: 0.33)
        case .youtube: return Color(red: 1.0, green: 0.0, blue: 0.0)
        case .plex: return Color(red: 0.89, green: 0.67, blue: 0.08)
        case .jellyfin: return Color(red: 0.0, green: 0.48, blue: 0.82)
        case .subsonic, .navidrome: return Color(red: 0.2, green: 0.6, blue: 0.86)
        case .filesystemLocal: return .gray
        case .sendspin: return .accentColor
        case .builtin: return .gray
        default: return .gray
        }
    }
}
