//
//  WallahApp.swift
//  Wallah
//
//  Created by 686udjie on 19/04/2026.
//

import AppKit
import UniformTypeIdentifiers

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var toggleItem: NSMenuItem!
    
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupMenu()
        WallahEngine.shared.setup()
    }
    
    func applicationWillTerminate(_ n: Notification) {
        WallahEngine.shared.restoreWallpapers()
    }

    private func setupMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "tv", accessibilityDescription: "Wallah")
        
        let menu = NSMenu()
        toggleItem = NSMenuItem(title: "Hide Wallpaper", action: #selector(toggle), keyEquivalent: "t")
        menu.addItem(toggleItem)
        menu.addItem(NSMenuItem(title: "Choose Video...", action: #selector(choose), keyEquivalent: "o"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate), keyEquivalent: "q"))
        statusItem.menu = menu
    }
    
    @objc func toggle() {
        WallahEngine.shared.isEnabled.toggle()
        toggleItem.title = WallahEngine.shared.isEnabled ? "Hide Wallpaper" : "Show Wallpaper"
    }
    
    @objc func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie]
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK {
            WallahEngine.shared.videoURL = panel.url
            toggleItem.title = "Hide Wallpaper"
        }
    }
}
