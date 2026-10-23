import AppKit
import MediaPlayer
import YTMusicKit

/// Bridges playback state to Control Center, the menu bar Now Playing widget
/// and hardware media keys.
@MainActor
final class NowPlayingCenter {
    private var artworkURL: URL?
    private var artwork: MPMediaItemArtwork?
    private var lastItemId: String?

    func configureCommands(_ player: PlaybackController) {
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.addTarget { [weak player] _ in player?.resume(); return .success }
        c.pauseCommand.addTarget { [weak player] _ in player?.pause(); return .success }
        c.togglePlayPauseCommand.addTarget { [weak player] _ in player?.togglePlayPause(); return .success }
        c.nextTrackCommand.addTarget { [weak player] _ in
            if PlayerEngine.debug { NSLog("[remote] nextTrack") }
            player?.next(); return .success
        }
        c.previousTrackCommand.addTarget { [weak player] _ in
            if PlayerEngine.debug { NSLog("[remote] previousTrack") }
            player?.previous(); return .success
        }
        c.changePlaybackPositionCommand.addTarget { [weak player] e in
            guard let e = e as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            player?.seek(to: e.positionTime)
            return .success
        }
        c.likeCommand.addTarget { [weak player] _ in
            guard let p = player, let cur = p.current else { return .noActionableNowPlayingItem }
            p.toggleLike(cur)
            return .success
        }
    }

    func update(_ p: PlaybackController, onlyTime: Bool = false) {
        let center = MPNowPlayingInfoCenter.default()
        guard let item = p.current else {
            center.nowPlayingInfo = nil
            center.playbackState = .stopped
            lastItemId = nil
            return
        }
        if onlyTime, lastItemId == item.id, var info = center.nowPlayingInfo {
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = p.time(at: .now)
            info[MPMediaItemPropertyPlaybackDuration] = p.duration
            info[MPNowPlayingInfoPropertyPlaybackRate] = p.isPlaying ? 1.0 : 0.0
            center.nowPlayingInfo = info
            center.playbackState = p.isPlaying ? .playing : .paused
            return
        }
        lastItemId = item.id
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: item.title,
            MPMediaItemPropertyArtist: item.artistLine,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: p.time(at: .now),
            MPMediaItemPropertyPlaybackDuration: p.duration,
            MPNowPlayingInfoPropertyPlaybackRate: p.isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
        if let album = item.album?.name { info[MPMediaItemPropertyAlbumTitle] = album }
        let url = item.artwork.url(size: 600)
        p.engine.setNowPlaying(title: item.title, artist: item.artistLine, album: item.album?.name, artworkURL: url)
        if url == artworkURL, let artwork { info[MPMediaItemPropertyArtwork] = artwork }
        center.nowPlayingInfo = info
        center.playbackState = p.isPlaying ? .playing : .paused

        if let url, url != artworkURL {
            artworkURL = url
            artwork = nil
            Task {
                guard let img = await ImagePipeline.shared.image(for: url), self.artworkURL == url else { return }
                let art = MPMediaItemArtwork(boundsSize: img.size) { _ in img }
                self.artwork = art
                var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                info[MPMediaItemPropertyArtwork] = art
                MPNowPlayingInfoCenter.default().nowPlayingInfo = info
            }
        }
    }
}
