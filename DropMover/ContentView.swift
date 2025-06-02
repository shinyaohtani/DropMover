//
//  ContentView.swift
//  DropMover
//
//  Created by 大谷伸弥 on 2025/06/02.
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    // MARK: - 画面表示用ステート
    @State private var droppedURLs: [URL] = []
    @State private var showDialog: Bool = false
    @State private var pendingShowDialog: Bool = false

    @State private var selectedDate: Date = Date()
    @State private var defaultDate: Date = Date()
    @State private var folderName: String = ""

    @State private var showResultAlert: Bool = false
    @State private var resultMessage: String = ""

    @AppStorage("parentFolderPath") private var parentFolderPath: String = ""

    private var computedParentFolderURL: URL {
        let fm = FileManager.default
        let rawPath = parentFolderPath.trimmingCharacters(in: .whitespacesAndNewlines)

        if !rawPath.isEmpty {
            let expanded = (rawPath as NSString).expandingTildeInPath
            let url = URL(fileURLWithPath: expanded, isDirectory: true)
            if !fm.fileExists(atPath: url.path) {
                try? fm.createDirectory(at: url, withIntermediateDirectories: true)
            }
            return url
        }

        let defaultURL = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents")
            .appendingPathComponent("DropMover")
        if !fm.fileExists(atPath: defaultURL.path) {
            try? fm.createDirectory(at: defaultURL, withIntermediateDirectories: true)
        }
        return defaultURL
    }

    // 日付文字列フォーマッタ
    private var dateFormatter: DateFormatter {
        let fmt = DateFormatter()
        fmt.calendar = Calendar(identifier: .gregorian)
        fmt.locale = Locale(identifier: "ja_JP")
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt
    }

    // プレビュー用の生成フォルダ名
    private var previewFolderName: String {
        let dateStr = dateFormatter.string(from: selectedDate)
        return "\(dateStr) \(folderName)"
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                // ① 背景画像をウィンドウいっぱいに表示
                Image("black-whole")
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .ignoresSafeArea()

                // ② ウィンドウ全体をドロップ領域にする透明オーバーレイ
                Color.clear
                    .contentShape(Rectangle()) // 透明でもドロップ判定が効くように
                    .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers -> Bool in
                        handleOnDrop(providers: providers)
                    }

                // ③ その上に「Drop files」テキストなど必要なUIを重ねる
                VStack {
                    Spacer()
                    Text("Drop files")
                        .font(.system(size: 24, weight: .regular))
                        .foregroundColor(Color.gray)
                        .offset(y: -20)
                    Spacer()
                }
            }
            // ④ selectedDate が更新され、pendingShowDialog が true のときにダイアログを開く
            .onChange(of: selectedDate) { newDate in
                if pendingShowDialog {
                    pendingShowDialog = false
                    showDialog = true
                }
            }
            // ⑤ ダイアログをモーダルで出す
            .sheet(isPresented: $showDialog, onDismiss: {
                droppedURLs.removeAll()
                folderName = ""
            }) {
                dialogView
            }
            // ⑥ 処理結果をアラートで表示
            .alert(isPresented: $showResultAlert) {
                Alert(
                    title: Text("DropMover"),
                    message: Text(resultMessage),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }

    // MARK: - ダイアログ（シート）本体
    private var dialogView: some View {
        VStack(spacing: 16) {
            Text("フォルダを作成してファイルを移動")
                .font(.headline)

            // 日付入力
            DatePicker("日付を選択:", selection: $selectedDate, displayedComponents: .date)
                .datePickerStyle(GraphicalDatePickerStyle())
                .frame(maxHeight: 250)

            // フォルダ名入力
            HStack {
                Text("フォルダ名:")
                TextField("フォルダ名を入力してください", text: $folderName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }

            // プレビュー表示
            HStack {
                Spacer()
                Text("生成フォルダ名: ")
                Text(previewFolderName)
                    .foregroundColor(folderName.isEmpty ? .gray : .primary)
                Spacer()
            }
            .font(.system(size: 14, weight: .light, design: .monospaced))

            Divider()

            // ボタン（キャンセル / 移動する）
            HStack {
                Button(action: {
                    showDialog = false
                }) {
                    Text("キャンセル")
                }
                Spacer()
                Button(action: {
                    performMoveAction()
                }) {
                    Text("移動する")
                }
                .disabled(folderName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 400)
    }

    // MARK: - ドロップ処理
    private func handleOnDrop(providers: [NSItemProvider]) -> Bool {
        var found = false
        let dispatchGroup = DispatchGroup()
        var tempURLs: [URL] = []

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                found = true
                dispatchGroup.enter()
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { (item, _) in
                    defer { dispatchGroup.leave() }
                    if let data = item as? Data,
                       let str = String(data: data, encoding: .utf8),
                       let url = URL(string: str) {
                        tempURLs.append(url)
                    } else if let url = item as? URL {
                        tempURLs.append(url)
                    }
                }
            }
        }

        dispatchGroup.notify(queue: .main) {
            if !tempURLs.isEmpty {
                self.droppedURLs = tempURLs
                let calcDate = computeEarliestDate(from: tempURLs)
                self.defaultDate = calcDate
                self.selectedDate = calcDate
                // selectedDate の更新を待ってからダイアログを開くフラグを立てる
                self.pendingShowDialog = true
            }
        }

        return found
    }

    // MARK: - 追加日と変更日のうち古い日時を使って、全ファイルの最古を取得
    private func computeEarliestDate(from urls: [URL]) -> Date {
        var dates: [Date] = []

        for url in urls {
            do {
                let res = try url.resourceValues(
                    forKeys: [.addedToDirectoryDateKey, .contentModificationDateKey]
                )
                let addedOpt = res.addedToDirectoryDate
                let modifiedOpt = res.contentModificationDate

                if let added = addedOpt, let modified = modifiedOpt {
                    dates.append(min(added, modified))
                } else if let added = addedOpt {
                    dates.append(added)
                } else if let modified = modifiedOpt {
                    dates.append(modified)
                } else {
                    dates.append(Date())
                }
            } catch {
                dates.append(Date())
            }
        }

        return dates.min() ?? Date()
    }

    // MARK: - 移動実行
    private func performMoveAction() {
        let fm = FileManager.default
        let dateStr = dateFormatter.string(from: selectedDate)
        var baseFolderName = "\(dateStr) \(folderName)"

        let parentURL = computedParentFolderURL
        var targetURL = parentURL.appendingPathComponent(baseFolderName)

        // 同名フォルダが存在する場合はサフィックスを付与してユニーク化
        var suffix = 1
        while fm.fileExists(atPath: targetURL.path) {
            suffix += 1
            baseFolderName = "\(dateStr) \(folderName) (\(suffix))"
            targetURL = parentURL.appendingPathComponent(baseFolderName)
        }

        var moveErrors: [String] = []

        do {
            // サブフォルダを作成
            try fm.createDirectory(at: targetURL, withIntermediateDirectories: true)

            // ファイル移動
            for srcURL in droppedURLs {
                let destURL = targetURL.appendingPathComponent(srcURL.lastPathComponent)
                do {
                    try fm.moveItem(at: srcURL, to: destURL)
                } catch {
                    moveErrors.append("・'\(srcURL.lastPathComponent)' の移動に失敗: \(error.localizedDescription)")
                }
            }

            // フォルダ本体のタイムスタンプを変更
            do {
                try setTimestamp(on: targetURL, date: selectedDate)
            } catch {
                moveErrors.append("・フォルダのタイムスタンプ変更に失敗: \(error.localizedDescription)")
            }

            if moveErrors.isEmpty {
                resultMessage = """
                \(baseFolderName)
                に移動しました。
                """
            } else {
                resultMessage = """
                一部ファイルの移動に失敗しました:
                \(moveErrors.joined(separator: "\n"))
                """
            }
        } catch {
            resultMessage = "フォルダ作成／タイムスタンプ変更に失敗: \(error.localizedDescription)"
        }

        showResultAlert = true
        showDialog = false
    }

    // MARK: - フォルダ本体のタイムスタンプを変更
    private func setTimestamp(on url: URL, date: Date) throws {
        var resourceValues = URLResourceValues()
        resourceValues.creationDate = date
        resourceValues.contentModificationDate = date
        var mutableURL = url
        try mutableURL.setResourceValues(resourceValues)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
