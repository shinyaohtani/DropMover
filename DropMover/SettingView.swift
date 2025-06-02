//
//  SettingsView.swift
//  DropMover
//
//  Created by 大谷伸弥 on 2025/06/02.
//

import SwiftUI

struct SettingsView: View {
    // ContentView で使う「移動先フォルダのパス」を UserDefaults 連携する
    @AppStorage("parentFolderPath") private var parentFolderPath: String = ""

    var body: some View {
        VStack(spacing: 20) {
            Text("設定")
                .font(.title2)
                .padding(.top, 20)

            HStack {
                Text("移動先フォルダ:")
                TextField("選択してください", text: $parentFolderPath)
                    .disabled(true)
                    .frame(minWidth: 300)

                Button("選択…") {
                    selectParentFolder()
                }
            }
            .padding(.horizontal, 20)

            Spacer()
        }
        .frame(width: 500, height: 150)
    }

    private func selectParentFolder() {
        let panel = NSOpenPanel()
        panel.title = "移動先フォルダを選択"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false

        if !parentFolderPath.isEmpty {
            let expanded = (parentFolderPath as NSString).expandingTildeInPath
            panel.directoryURL = URL(fileURLWithPath: expanded, isDirectory: true)
        } else {
            panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Documents")
        }

        if panel.runModal() == .OK, let url = panel.url {
            parentFolderPath = url.path
        }
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
