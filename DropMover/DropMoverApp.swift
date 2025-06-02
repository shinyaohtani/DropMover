//
//  DropMoverApp.swift
//  DropMover
//
//  Created by 大谷伸弥 on 2025/06/02.
//

import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // WindowGroup で最初に作られるウインドウを取得
        guard let window = NSApp.windows.first else { return }

        // SwiftUI のコンテントビュー（NSHostingView）を取得し、
        // fileURL タイプのドラッグを受け取るように登録する
        if let hostingView = window.contentView {
            hostingView.registerForDraggedTypes([.fileURL])
        }
    }
}


@main
struct DropMoverApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 722, minHeight: 482)
        }
        .windowStyle(HiddenTitleBarWindowStyle()) // タイトルバーを隠して Drop 表示だけにする例
    }
}
