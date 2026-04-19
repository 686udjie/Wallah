//
//  WallahEngine.swift
//  Wallah
//
//  Created by 686udjie on 19/04/2026.
//

import AppKit
import AVFoundation

class WallahEngine {
    static let shared = WallahEngine()
    
    private var window: NSWindow?
    private var player: AVPlayer?
    private var originalWallpapers: [NSScreen: URL] = [:]
    
    var isEnabled = true { didSet { updateState() } }
    
    var videoURL: URL? {
        get { UserDefaults.standard.string(forKey: "videoPath").map { URL(fileURLWithPath: $0) } }
        set { 
            UserDefaults.standard.set(newValue?.path, forKey: "videoPath")
            setupEngine()
        }
    }

    func setup() {
        // Capture original wallpapers
        NSScreen.screens.forEach { screen in
            if let url = NSWorkspace.shared.desktopImageURL(for: screen), url.lastPathComponent != "snapshot.png" {
                originalWallpapers[screen] = url
            }
        }
        
        setupWindow()
        setupEngine()
        
        // Watch for space changes to keep video playing and window behind
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.updateState()
        }
    }
    
    private func setupWindow() {
        guard let screen = NSScreen.main else { return }
        let win = NSWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        win.backgroundColor = .clear
        win.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        win.ignoresMouseEvents = true
        win.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        win.contentView = NSView(frame: screen.frame)
        win.makeKeyAndOrderFront(nil)
        self.window = win
    }
    
    private func setupEngine() {
        guard let view = window?.contentView, let url = videoURL ?? Bundle.main.url(forResource: "wallpaper", withExtension: "mp4") else { return }
        
        player?.pause()
        player = AVPlayer(url: url)
        player?.isMuted = true
        player?.actionAtItemEnd = .none
        
        let layer = AVPlayerLayer(player: player)
        layer.frame = view.bounds
        layer.videoGravity = .resizeAspectFill
        
        view.wantsLayer = true
        view.layer = CALayer()
        view.layer?.addSublayer(layer)
        
        syncWallpaper(url: url)
        
        NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: player?.currentItem, queue: .main) { [weak self] _ in
            self?.player?.seek(to: .zero)
            self?.player?.play()
        }
        
        updateState()
    }
    
    func updateState() {
        guard let win = window else { return }
        if isEnabled {
            win.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
            win.orderFront(nil)
            player?.play()
            if let url = videoURL ?? Bundle.main.url(forResource: "wallpaper", withExtension: "mp4") {
                syncWallpaper(url: url)
            }
        } else {
            win.orderOut(nil)
            player?.pause()
            restoreWallpapers()
        }
    }
    
    func restoreWallpapers() {
        originalWallpapers.forEach { runAppleScript("tell application \"System Events\" to tell every desktop to set picture to \"\($1.path)\"") }
    }
    
    private func syncWallpaper(url: URL) {
        DispatchQueue.global(qos: .background).async {
            let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("Wallah")
            try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
            
            let snapshot = supportDir.appendingPathComponent("snapshot.png")
            let ql = Process()
            ql.executableURL = URL(fileURLWithPath: "/usr/bin/qlmanage")
            ql.arguments = ["-t", "-s", "3840", "-o", supportDir.path, url.path]
            try? ql.run()
            ql.waitUntilExit()
            
            let thumb = supportDir.appendingPathComponent(url.lastPathComponent + ".png")
            if FileManager.default.fileExists(atPath: thumb.path) {
                try? FileManager.default.removeItem(at: snapshot)
                try? FileManager.default.moveItem(at: thumb, to: snapshot)
                self.runAppleScript("tell application \"System Events\" to tell every desktop to set picture to \"\(snapshot.path)\"")
            }
        }
    }
    
    private func runAppleScript(_ source: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", source]
        try? p.run()
    }
}
