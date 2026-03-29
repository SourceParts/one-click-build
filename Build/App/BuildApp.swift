import SwiftUI

@main
struct BuildApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var pipeline = BuildPipeline()

    var body: some Scene {
        WindowGroup("Build") {
            BuildView()
                .environmentObject(pipeline)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 900, height: 650)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
