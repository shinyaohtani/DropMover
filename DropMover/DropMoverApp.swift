//
//  DropMoverApp.swift
//  DropMover
//
//  Created by 大谷伸弥 on 2025/06/02.
//

import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 最初のウィンドウを取得
        guard let window = NSApp.windows.first else { return }
        DispatchQueue.main.async {
            window.setContentSize(NSSize(width: 360, height: 240))
            window.minSize = NSSize(width: 360, height: 240)
            window.maxSize = NSSize(width: 360, height: 240)
            window.styleMask.remove(.resizable)

            if let hostingView = window.contentView {
                hostingView.registerForDraggedTypes([.fileURL])
            }
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

@main
struct DropMoverApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(HiddenTitleBarWindowStyle())
    }
}
