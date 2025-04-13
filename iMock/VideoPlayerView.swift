//
//  VideoPlayerView.swift
//  SpotifyVideoPlayer
//
//  Created by Ronaldo Avalos on 24/03/25.
//


import SwiftUI
import AVKit

struct VideoPlayerView: View {
    @State private var player = AVPlayer()
    let video: Video
    var size: CGSize

    var body: some View {
        VideoPlayerNSView(player: player, size: size)
            .onAppear {
                loadVideoFile()
                addLooping()
                player.play()
                player.isMuted = true
            }
    }

    private func loadVideoFile() {
        let playerItem = AVPlayerItem(url: video.videoID)
        player.replaceCurrentItem(with: playerItem)
        player.isMuted = true
    }

    private func addLooping() {
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { _ in
            player.seek(to: .zero)
            player.isMuted = true
            player.play()
        }
    }
}
struct VideoPlayerNSView: NSViewRepresentable {
    var player: AVPlayer
    var size: CGSize

    func makeNSView(context: Context) -> NSView {
        let hostingView = NSView()
        hostingView.wantsLayer = true
        hostingView.layer?.cornerRadius = 40
        hostingView.layer?.masksToBounds = true

        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.videoGravity = .resizeAspectFill
        hostingView.layer?.addSublayer(playerLayer)

        return hostingView
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let playerLayer = nsView.layer?.sublayers?.first(where: { $0 is AVPlayerLayer }) as? AVPlayerLayer else { return }

        // 🟡 Redimensiona correctamente
        nsView.setFrameSize(size)
        playerLayer.frame = CGRect(origin: .zero, size: size)
    }
}
