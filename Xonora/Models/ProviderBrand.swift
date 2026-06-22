import SwiftUI

enum ProviderBrand: String, CaseIterable {
    case spotify, qobuz, tidal, deezer, appleMusic = "apple_music"
    case youtube, soundcloud, bandcamp, plex, emby
    case jellyfin, subsonic, navidrome, filesystemLocal = "filesystem_local"
    case airplay, chromecast, dlna, sonos, squeezebox, snapcast, slimproto = "slimproto"
    case sendspin, builtin, test, unknown
    case web, universalPlayer

    init(provider: String, type: String = "", name: String = "") {
        let lower = provider.lowercased()
        let typeLower = type.lowercased()
        let nameLower = name.lowercased()

        // Web/browser player: MA sends type="web", or name contains browser keywords
        if typeLower == "web" || (lower == "sendspin" && (nameLower.contains("web") || nameLower.contains("chrome") || nameLower.contains("firefox") || nameLower.contains("safari") || nameLower.contains("edge"))) {
            self = .web
        } else if lower == "snapcast" { self = .snapcast }
        else if lower == "slimproto" { self = .slimproto }
        else if lower == "sonos_s1" || lower == "sonos_s2" { self = .sonos }
        else if lower == "squeezebox" { self = .squeezebox }
        else if lower == "universal_player" { self = .universalPlayer }
        else { self = ProviderBrand(rawValue: lower) ?? .unknown }
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
        case .snapcast: return "Snapcast"
        case .slimproto: return "Squeezebox"
        case .sendspin: return "Sendspin"
        case .builtin: return "Built-in"
        case .test: return "Test"
        case .unknown: return "Unknown"
        case .web: return "Web"
        case .universalPlayer: return "Music Assistant"
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
        case .snapcast: return "speaker.wave.2"
        case .slimproto: return "rectangle.3.group"
        case .sendspin: return "iphone"
        case .builtin: return "speaker.wave.2"
        case .test: return "wrench"
        case .unknown: return "questionmark.circle"
        case .web: return "globe"
        case .universalPlayer: return "hifispeaker"
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
        case .soundcloud: return Color(red: 1.0, green: 0.49, blue: 0.0)
        case .bandcamp: return Color(red: 0.25, green: 0.47, blue: 0.82)
        case .emby: return Color(red: 0.0, green: 0.55, blue: 0.70)
        case .airplay: return Color(red: 0.4, green: 0.4, blue: 0.4)
        case .chromecast: return Color(red: 0.0, green: 0.64, blue: 0.28)
        case .dlna: return Color(red: 0.0, green: 0.38, blue: 0.66)
        case .sonos: return Color(red: 0.0, green: 0.0, blue: 0.0)
        case .squeezebox: return Color(red: 0.12, green: 0.55, blue: 0.82)
        case .snapcast: return Color(red: 0.82, green: 0.35, blue: 0.0)
        case .slimproto: return Color(red: 0.12, green: 0.55, blue: 0.82)
        case .sendspin: return .accentColor
        case .builtin: return .gray
        case .test: return Color(red: 0.6, green: 0.6, blue: 0.6)
        case .web: return Color(red: 0.0, green: 0.48, blue: 1.0)
        case .universalPlayer: return .accentColor
        case .unknown: return .gray
        }
    }
}
