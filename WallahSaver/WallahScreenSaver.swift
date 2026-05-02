//
//  WallahScreenSaver.swift
//  Wallah
//
//  Created by 686udjie on 02/05/2026.
//

import ScreenSaver
import AVFoundation
import AppKit

class WallahScreenSaverView: ScreenSaverView {
    private var player: AVQueuePlayer?
    private var playerLooper: AVPlayerLooper?
    private var playerLayer: AVPlayerLayer?

    private var videoURL: URL? {
        let defaults = UserDefaults(suiteName: "com.wallah.app.Wallah")
        return defaults?.string(forKey: "videoPath").map { URL(fileURLWithPath: $0) }
            ?? Bundle.main.url(forResource: "wallpaper", withExtension: "mp4")
    }

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        self.wantsLayer = true
        self.layer = CALayer()
        self.layer?.backgroundColor = NSColor.black.cgColor

        guard let url = videoURL else { return }

        // Setup the player
        let playerItem = AVPlayerItem(url: url)
        let queuePlayer = AVQueuePlayer(playerItem: playerItem)
        queuePlayer.isMuted = true
        
        // Loop the video flawlessly
        self.playerLooper = AVPlayerLooper(player: queuePlayer, templateItem: playerItem)
        self.player = queuePlayer

        // Setup the layer
        let videoLayer = AVPlayerLayer(player: queuePlayer)
        videoLayer.frame = self.bounds
        videoLayer.videoGravity = .resizeAspectFill
        videoLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        
        self.layer?.addSublayer(videoLayer)
        self.playerLayer = videoLayer

        // Start playback
        queuePlayer.play()
    }

    override func startAnimation() {
        super.startAnimation()
        player?.play()
    }

    override func stopAnimation() {
        super.stopAnimation()
        player?.pause()
    }

    override var hasConfigureSheet: Bool { false }
    override var configureSheet: NSWindow? { nil }
}
