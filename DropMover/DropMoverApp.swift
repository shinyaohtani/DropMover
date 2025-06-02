//
//  DropMoverApp.swift
//  DropMover
//
//  Created by 大谷伸弥 on 2025/06/02.
//

import SwiftUI

@main
struct DropMoverApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 722, minHeight: 482)
        }
        .windowStyle(HiddenTitleBarWindowStyle()) // タイトルバーを隠して Drop 表示だけにする例
    }
}
