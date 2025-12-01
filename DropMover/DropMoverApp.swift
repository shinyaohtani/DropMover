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

// MARK: - Finder Extension Status Checker

enum FinderExtensionStatus {
    case enabled
    case disabled
    case notFound
}

enum FinderExtensionChecker {
    private static let extensionBundleID = "com.aabce.DropMover.FinderExtension"

    /// Finder拡張機能の有効/無効状態を確認
    static func checkStatus() -> FinderExtensionStatus {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
        process.arguments = ["-m", "-p", "com.apple.FinderSync"]
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else {
                return .notFound
            }

            // 出力から該当の拡張機能を探す
            // 形式: "+    com.aabce.DropMover.FinderExtension(1.0)" (有効)
            //       "-    com.aabce.DropMover.FinderExtension(1.0)" (無効)
            //       "     com.aabce.DropMover.FinderExtension(1.0)" (未設定)
            for line in output.components(separatedBy: "\n") {
                if line.contains(extensionBundleID) {
                    if line.hasPrefix("+") {
                        return .enabled
                    } else {
                        return .disabled
                    }
                }
            }

            return .notFound
        } catch {
            return .notFound
        }
    }

    /// システム設定の機能拡張画面を開く
    static func openExtensionSettings() {
        // macOS 13以降の設定アプリURL
        if let url = URL(string: "x-apple.systempreferences:com.apple.ExtensionsPreferences") {
            NSWorkspace.shared.open(url)
        }
    }
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
