//
//  DropMoverApp.swift
//  DropMover
//
//  Created by 大谷伸弥 on 2025/06/02.
//

import SwiftUI

extension Notification.Name {
    static let didReceiveFilesOnIcon = Notification.Name("didReceiveFilesOnIcon")
}

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
    func application(_ application: NSApplication, open urls: [URL]) {
        // URLスキーム（dropmover://）かファイルURLかを判定
        let fileURLs = urls.flatMap { url -> [URL] in
            if url.scheme == "dropmover" {
                // dropmover://move?files=path1&files=path2 形式を解析
                return parseDropMoverURL(url)
            } else {
                // 通常のファイルURL
                return [url]
            }
        }

        guard !fileURLs.isEmpty else { return }

        // Notification で ContentView に URL リストを投げる
        NotificationCenter.default.post(
            name: .didReceiveFilesOnIcon,
            object: nil,
            userInfo: ["urls": fileURLs]
        )
    }

    /// dropmover:// URLスキームをパースしてファイルURLの配列を返す
    private func parseDropMoverURL(_ url: URL) -> [URL] {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            return []
        }

        return queryItems
            .filter { $0.name == "file" }
            .compactMap { item -> URL? in
                guard let path = item.value?.removingPercentEncoding else { return nil }
                return URL(fileURLWithPath: path)
            }
    }
}

@main
struct DropMoverApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Window("DropMover", id: "main") {
            ContentView()
        }
        .windowStyle(HiddenTitleBarWindowStyle())

        Settings {
            SettingsView()
        }
    }
}
