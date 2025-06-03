//
//  ContentView.swift
//  DropMover
//
//  Created by 大谷伸弥 on 2025/06/02.
//

import SwiftUI
import UniformTypeIdentifiers

// ドロップされたファイル一覧と計算済み日付を保持するコンテキスト
struct DropContext: Identifiable {
    let id = UUID()
    let urls: [URL]
    let defaultDate: Date
}

struct ContentView: View {
    // MARK: - 画面表示用ステート
    // DropContext が非 nil になるとシート表示をトリガー
    @State private var dropContext: DropContext? = nil

    // フォルダを移動した後に結果をアラート表示するためのステート
    @State private var showResultAlert: Bool = false
    @State private var resultMessage: String = ""

    @AppStorage("parentFolderPath") private var parentFolderPath: String = ""

    // UserDefaults に保存された移動先フォルダのパスを計算して返す
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
                    .contentShape(Rectangle())
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
            // ④ DropContext がセットされたらシートを表示
            .sheet(item: $dropContext, onDismiss: {
                // シートを閉じたら dropContext を nil に戻し、フォルダ名などは SheetView 側でリセット
                dropContext = nil
            }) { context in
                // シート初期化時に必ず defaultDate を渡す
                SheetView(
                    initialDate: context.defaultDate,
                    droppedURLs: context.urls,
                    parentFolderURL: computedParentFolderURL,
                    onFinish: { message in
                        // SheetView で移動完了後にメッセージを受け取りアラート表示
                        resultMessage = message
                        showResultAlert = true
                    }
                )
            }
            // ⑤ 処理結果をアラートで表示
            .alert(isPresented: $showResultAlert) {
                Alert(
                    title: Text("DropMover"),
                    message: Text(resultMessage),
                    dismissButton: .default(Text("OK"))
                )
            }
            // ⑥ Dock / Finder アイコンにファイルをドロップされた場合の通知を受け取る
            .onReceive(NotificationCenter.default.publisher(for: .didReceiveFilesOnIcon)) { notification in
                guard
                    let userInfo = notification.userInfo,
                    let urls = userInfo["urls"] as? [URL]
                else { return }
                handleIncomingURLs(urls)
            }
        }
    }

    // MARK: - ドラッグ＆ドロップ（ウィンドウ内）処理
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
                let calcDate = computeEarliestDate(from: tempURLs)
                // DropContext を作成してシート表示をトリガー
                dropContext = DropContext(urls: tempURLs, defaultDate: calcDate)
            }
        }

        return found
    }

    // MARK: - Dock / Finder アイコンにドロップされたファイルを受け取る処理
    private func handleIncomingURLs(_ urls: [URL]) {
        let calcDate = computeEarliestDate(from: urls)
        dropContext = DropContext(urls: urls, defaultDate: calcDate)
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
}

// MARK: - SheetView: シート表示用ビュー
struct SheetView: View {
    // 初期表示用の日付と、ドロップされた URL リスト
    let initialDate: Date
    let droppedURLs: [URL]
    let parentFolderURL: URL
    // 完了後にメッセージを返すクロージャ
    let onFinish: (String) -> Void

    // シート内で選択された日付とフォルダ名を保持
    @State private var selectedDate: Date
    @State private var folderName: String = ""

    // アラート表示用
    @State private var showResultAlert: Bool = false
    @State private var resultMessage: String = ""

    // イニシャライザで初期値をセット
    init(
        initialDate: Date,
        droppedURLs: [URL],
        parentFolderURL: URL,
        onFinish: @escaping (String) -> Void
    ) {
        self.initialDate = initialDate
        self.droppedURLs = droppedURLs
        self.parentFolderURL = parentFolderURL
        self.onFinish = onFinish
        self._selectedDate = State(initialValue: initialDate)
    }

    // 日付文字列フォーマッタ
    private var dateFormatter: DateFormatter {
        let fmt = DateFormatter()
        fmt.calendar = Calendar(identifier: .gregorian)
        fmt.locale = Locale(identifier: "ja_JP")
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt
    }

    // プレビュー用フォルダ名
    private var previewFolderName: String {
        let dateStr = dateFormatter.string(from: selectedDate)
        return "\(dateStr) \(folderName)"
    }

    var body: some View {
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
                Button("キャンセル") {
                    // シートを閉じる
                    NSApp.keyWindow?.firstResponder?.tryToPerform(
                        #selector(NSWindow.cancelOperation(_:)),
                        with: nil
                    )
                }
                Spacer()
                Button("移動する") {
                    performMoveAction()
                }
                .disabled(folderName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 400)
        .alert(isPresented: $showResultAlert) {
            Alert(
                title: Text("DropMover"),
                message: Text(resultMessage),
                dismissButton: .default(Text("OK")) {
                    // 移動処理が終わったら、親ビュー(ContentView)にメッセージを渡して閉じる
                    onFinish(resultMessage)
                    NSApp.keyWindow?.firstResponder?.tryToPerform(
                        #selector(NSWindow.cancelOperation(_:)),
                        with: nil
                    )
                }
            )
        }
    }

    // MARK: - 移動実行の本体
    private func performMoveAction() {
        let fm = FileManager.default
        let dateStr = dateFormatter.string(from: selectedDate)
        var baseFolderName = "\(dateStr) \(folderName)"
        var targetURL = parentFolderURL.appendingPathComponent(baseFolderName)

        // 同名フォルダが存在する場合はサフィックスを付与
        var suffix = 1
        while fm.fileExists(atPath: targetURL.path) {
            suffix += 1
            baseFolderName = "\(dateStr) \(folderName) (\(suffix))"
            targetURL = parentFolderURL.appendingPathComponent(baseFolderName)
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
                var resourceValues = URLResourceValues()
                resourceValues.creationDate = selectedDate
                resourceValues.contentModificationDate = selectedDate
                var mutableURL = targetURL
                try mutableURL.setResourceValues(resourceValues)
            } catch {
                moveErrors.append("・フォルダのタイムスタンプ変更に失敗: \(error.localizedDescription)")
            }

            if moveErrors.isEmpty {
                resultMessage = "すべてのファイルを「\(baseFolderName)」へ移動しました。"
            } else {
                resultMessage = "一部ファイルの移動に失敗しました:\n" + moveErrors.joined(separator: "\n")
            }
        } catch {
            resultMessage = "フォルダ作成／タイムスタンプ変更に失敗: \(error.localizedDescription)"
        }

        showResultAlert = true
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
