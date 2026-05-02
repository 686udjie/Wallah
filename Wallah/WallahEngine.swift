//
//  WallahEngine.swift
//  Wallah
//
//  Created by 686udjie on 19/04/2026.
//

import AppKit
import AVFoundation

// MARK: - Logger

class Logger {
    static let shared = Logger()
    private let logURL = URL(fileURLWithPath: "/tmp/wallah_debug.log")

    private init() {
        try? FileManager.default.removeItem(at: logURL)
    }

    func log(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let formattedMessage = "[\(timestamp)] \(message)\n"
        
        print(formattedMessage, terminator: "")
        
        guard let data = formattedMessage.data(using: .utf8) else { return }
        
        if FileManager.default.fileExists(atPath: logURL.path),
           let fileHandle = try? FileHandle(forWritingTo: logURL) {
            fileHandle.seekToEndOfFile()
            fileHandle.write(data)
            try? fileHandle.close()
        } else {
            try? data.write(to: logURL)
        }
    }
}

// MARK: - FrameEngine

class FrameEngine {
    private(set) var duration: Double = 0
    private var frames: [CGImage?] = []
    private var fps: Double = 30.0

    init(url: URL, progressHandler: ((Double) -> Void)? = nil, completion: @escaping () -> Void) {
        Task {
            await preloadFrames(from: url, progressHandler: progressHandler, completion: completion)
        }
    }

    func frame(at seconds: Double) -> CGImage? {
        guard !frames.isEmpty, fps > 0 else { return nil }
        let index = Int(seconds * fps) % frames.count
        
        if let exactFrame = frames[index] {
            return exactFrame
        }
        
        for i in stride(from: index, through: 0, by: -1) {
            if let fallback = frames[i] {
                return fallback
            }
        }
        return nil
    }
    
    // MARK: Private Helpers

    private func preloadFrames(from url: URL, progressHandler: ((Double) -> Void)?, completion: @escaping () -> Void) async {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        generator.maximumSize = CGSize(width: 1920, height: 1080)
        
        do {
            self.duration = try await asset.load(.duration).seconds
            
            if let track = try await asset.loadTracks(withMediaType: .video).first {
                self.fps = Double(try await track.load(.nominalFrameRate))
            }
            
            let frameCount = Int(self.duration * self.fps)
            let interval = 1.0 / self.fps
            let times = (0..<frameCount).map { index in
                NSValue(time: CMTime(seconds: Double(index) * interval, preferredTimescale: 600))
            }
            
            await extractCGImages(from: generator, times: times, frameCount: frameCount, progressHandler: progressHandler, completion: completion)
            
        } catch {
            Logger.shared.log("FrameEngine init error: \(error)")
            DispatchQueue.main.async { completion() }
        }
    }
    
    private func extractCGImages(
        from generator: AVAssetImageGenerator,
        times: [NSValue],
        frameCount: Int,
        progressHandler: ((Double) -> Void)?,
        completion: @escaping () -> Void
    ) async {
        var loaded = 0
        self.frames = Array(repeating: CGImage?.none, count: frameCount)
        let queue = DispatchQueue(label: "frame.preload")
        DispatchQueue.main.async { completion() }
        
        generator.generateCGImagesAsynchronously(forTimes: times) { requestedTime, cgImage, _, result, _ in
            queue.async {
                defer {
                    loaded += 1
                    if loaded % max(1, frameCount / 10) == 0 || loaded == frameCount {
                        progressHandler?(Double(loaded) / Double(frameCount))
                    }
                }
                
                guard result == .succeeded, let cgImage = cgImage else { return }
                
                let index = Int(requestedTime.seconds * self.fps + 0.5)
                if index < self.frames.count {
                    self.frames[index] = cgImage
                }
            }
        }
    }
}

// MARK: - WallpaperSetter

class WallpaperSetter {
    private static var isReloading = false
    private static var framesSinceReload = 0
    private static let reloadInterval = 1

    static let wallpaperURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("com.apple.wallpaper/wallpaper.png")
    }()

    static func setup(firstFrame: CGImage) {
        set(cgImage: firstFrame, isLocked: false)
        Logger.shared.log("Setup written to \(wallpaperURL.path)")
    }

    static func set(cgImage: CGImage, isLocked: Bool) {
        guard let dest = CGImageDestinationCreateWithURL(
            wallpaperURL as CFURL,
            "public.png" as CFString,
            1, nil
        ) else { return }
        
        CGImageDestinationAddImage(dest, cgImage, nil)
        CGImageDestinationFinalize(dest)

        guard isLocked else { return }

        framesSinceReload += 1
        guard framesSinceReload >= reloadInterval, !isReloading else { return }
        
        framesSinceReload = 0
        isReloading = true

        restartWallpaperAgent()
    }

    static func pinURL() {
        NSScreen.screens.forEach { screen in
            try? NSWorkspace.shared.setDesktopImageURL(wallpaperURL, for: screen, options: [:])
        }
    }
    
    // MARK: Private Helpers

    private static func restartWallpaperAgent() {
        DispatchQueue.global(qos: .userInteractive).async {
            let process = Process()
            process.launchPath = "/usr/bin/killall"
            process.arguments = ["WallpaperAgent"]
            try? process.run()
            process.waitUntilExit()

            // Wait for WallpaperAgent to restart before repinning
            Thread.sleep(forTimeInterval: 0.4)

            DispatchQueue.main.async {
                pinURL()
                isReloading = false
                Logger.shared.log("WallpaperAgent restarted and URL re-pinned")
            }
        }
    }
}

// MARK: - WallahEngine

class WallahEngine {
    static let shared = WallahEngine()

    // MARK: Public Properties
    
    var isEnabled = true { didSet { updateState() } }
    var isLocked = false { 
        didSet { 
            updateTimerRate()
            updateWindowLevel()
        } 
    }
    var videoURL: URL? {
        get { UserDefaults.standard.string(forKey: "videoPath").map { URL(fileURLWithPath: $0) } }
        set {
            UserDefaults.standard.set(newValue?.path, forKey: "videoPath")
            setupEngine()
        }
    }

    // MARK: Private State
    
    private var window: NSWindow?
    private var player: AVPlayer?
    private var originalWallpapers: [NSScreen: URL] = [:]
    private var timer: Timer?
    private var activity: NSObjectProtocol?
    private var engine: FrameEngine?
    private var manualTime: Double = 0
    private var videoDuration: Double = 0
    private var hasLogged = false

    // MARK: Lifecycle

    func setup() {
        Logger.shared.log("WallahEngine setup started")

        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .latencyCritical],
            reason: "Lockscreen rendering engine"
        )

        setupNotifications()
        captureOriginalWallpapers()
        
        setupWindow()
        setupEngine()
    }

    func updateState() {
        guard let window = window else { return }
        
        if isEnabled {
            window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
            window.orderFront(nil)
            player?.play()
            
            if engine == nil, let url = videoURL ?? Bundle.main.url(forResource: "wallpaper", withExtension: "mp4") {
                startWallpaperLoop(url: url)
            }
        } else {
            window.orderOut(nil)
            player?.pause()
            timer?.invalidate()
            engine = nil
            restoreWallpapers()
        }
    }

    func startWallpaperLoop(url: URL) {
        hasLogged = false
        manualTime = 0
        engine = nil
        timer?.invalidate()

        Logger.shared.log("Preloading frames...")

        engine = FrameEngine(url: url, progressHandler: { progress in
            Logger.shared.log(String(format: "Preload: %d%%", Int(progress * 100)))
        }, completion: { [weak self] in
            guard let self = self else { return }
            
            Logger.shared.log("Preload complete.")
            self.videoDuration = self.engine?.duration ?? 0

            if let firstFrame = self.engine?.frame(at: 0) {
                WallpaperSetter.setup(firstFrame: firstFrame)
            }

            self.updateTimerRate()
        })
    }

    func updateTimerRate() {
        guard isEnabled, let engine = self.engine else { return }
        timer?.invalidate()

        let fps: Double = isLocked ? 4.0 : 30.0
        let interval = 1.0 / fps
        Logger.shared.log("Timer set to \(fps) FPS")

        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            if let self = self {
                self.handleTimerTick(interval: interval, engine: engine)
            }
        }
    }

    private func updateWindowLevel() {
        guard let window = window else { return }
        if isLocked {
            window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)))
        } else {
            window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        }
    }

    // MARK: Private Helpers
    
    private func setupNotifications() {
        let center = DistributedNotificationCenter.default()
        
        center.addObserver(forName: NSNotification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            self?.isLocked = true
            Logger.shared.log("Screen locked.")
        }

        center.addObserver(forName: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            self?.isLocked = false
            Logger.shared.log("Screen unlocked.")
            WallpaperSetter.pinURL()
        }

        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.updateState()
        }
    }

    private func captureOriginalWallpapers() {
        NSScreen.screens.forEach { screen in
            if let url = NSWorkspace.shared.desktopImageURL(for: screen),
               url.path != WallpaperSetter.wallpaperURL.path {
                originalWallpapers[screen] = url
            }
        }
    }

    private func setupWindow() {
        guard let screen = NSScreen.main else { return }
        
        let win = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        win.backgroundColor = .clear
        win.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        win.ignoresMouseEvents = true
        win.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        win.contentView = NSView(frame: screen.frame)
        win.makeKeyAndOrderFront(nil)
        
        self.window = win
    }

    private func setupEngine() {
        guard let view = window?.contentView,
              let url = videoURL ?? Bundle.main.url(forResource: "wallpaper", withExtension: "mp4")
        else { return }

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

        NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: player?.currentItem, queue: .main) { [weak self] _ in
            self?.player?.seek(to: .zero)
            self?.player?.play()
        }

        updateState()
    }

    private func handleTimerTick(interval: Double, engine: FrameEngine) {
        guard let player = self.player else { return }

        if !hasLogged {
            Logger.shared.log("Timer fired.")
            hasLogged = true
        }

        let currentTime: Double
        if player.rate == 0 || isLocked {
            manualTime += interval
            if videoDuration > 0 && manualTime >= videoDuration {
                manualTime = 0
            }
            currentTime = manualTime
        } else {
            currentTime = player.currentTime().seconds
            manualTime = currentTime
        }

        if let cgImage = engine.frame(at: currentTime) {
            WallpaperSetter.set(cgImage: cgImage, isLocked: isLocked)
        } else {
            manualTime = 0
        }
    }

    func restoreWallpapers() {
        originalWallpapers.forEach { screen, url in
            try? NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])
        }
    }
}
