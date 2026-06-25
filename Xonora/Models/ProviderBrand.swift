import SwiftUI

enum ProviderBrand: String, CaseIterable {
    case spotify, qobuz, tidal, deezer, appleMusic = "apple_music"
    case youtube, soundcloud, bandcamp, plex, emby
    case jellyfin, subsonic, navidrome, filesystemLocal = "filesystem_local"
    case airplay, chromecast, dlna, sonos, squeezebox, snapcast, slimproto = "slimproto"
    case sendspin, builtin, test, unknown
    case web, universalPlayer
    case neteasecloudmusic = "netease"
    case loudnessAnalysis = "loudness_analysis"
    case localAudioOut = "local_audio_out"
    case itunesArtwork = "itunes_artwork"
    case coverArtArchive = "cover_art_archive"
    case fanartTV, syncGroupPlayer = "sync_group_player"
    case theAudioDB = "theaudiodb"
    case wikipedia, musicbrainz, lrclib
    case party_mode = "party"
    case lastfm

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
        else if lower == "universal_player" || lower == "music_assistant" { self = .universalPlayer }
        else if lower == "neteasecloudmusic" || lower == "netease" { self = .neteasecloudmusic }
        else if lower == "fanart.tv" || lower == "fanart_tv" { self = .fanartTV }
        else if lower == "last.fm" || lower == "lastfm" { self = .lastfm }
        else if lower == "theaudiodb" { self = .theAudioDB }
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
        case .neteasecloudmusic: return "NetEase Cloud Music"
        case .loudnessAnalysis: return "Loudness Analysis"
        case .localAudioOut: return "Local Audio"
        case .itunesArtwork: return "iTunes Artwork"
        case .coverArtArchive: return "Cover Art Archive"
        case .fanartTV: return "fanart.tv"
        case .syncGroupPlayer: return "Sync Group"
        case .theAudioDB: return "TheAudioDB"
        case .wikipedia: return "Wikipedia"
        case .musicbrainz: return "MusicBrainz"
        case .lrclib: return "LRCLIB"
        case .party_mode: return "Party Mode"
        case .lastfm: return "Last.fm"
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
        case .neteasecloudmusic: return "music.note.list"
        case .loudnessAnalysis: return "waveform.path.ecg"
        case .localAudioOut: return "cable.connector"
        case .itunesArtwork: return "photo.artframe"
        case .coverArtArchive: return "photo.on.rectangle"
        case .fanartTV: return "photo.tv"
        case .syncGroupPlayer: return "speaker.wave.2.fill"
        case .theAudioDB: return "music.note.list"
        case .wikipedia: return "book.pages"
        case .musicbrainz: return "brain.head.profile"
        case .lrclib: return "text.quote"
        case .party_mode: return "music.note.house"
        case .lastfm: return "dot.radiowaves.left.and.right"
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
        case .neteasecloudmusic: return Color(red: 0.86, green: 0.08, blue: 0.08)
        case .loudnessAnalysis, .localAudioOut, .syncGroupPlayer: return .accentColor
        case .itunesArtwork, .coverArtArchive, .fanartTV: return Color(red: 0.2, green: 0.5, blue: 0.9)
        case .theAudioDB, .wikipedia, .musicbrainz: return Color(red: 0.4, green: 0.4, blue: 0.8)
        case .lrclib: return Color(red: 0.5, green: 0.3, blue: 0.8)
        case .party_mode: return .orange
        case .lastfm: return Color(red: 0.82, green: 0.1, blue: 0.1)
        }
}
}
