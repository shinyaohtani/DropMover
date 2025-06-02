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
    @State private var selectedDate: Date = Date()
    @State private var folderName: String = ""
    @State private var defaultDate: Date = Date()
    
    @State private var showResultAlert: Bool = false
    @State private var resultMessage: String = ""
    
    // 親フォルダ（生成先）のデフォルトパス
    // 必要があれば後で設定画面などから変更可能にする
    private var parentFolderURL: URL {
        let fm = FileManager.default
        let docs = fm.homeDirectoryForCurrentUser.appendingPathComponent("Documents/DropMover")
        if !fm.fileExists(atPath: docs.path) {
            // 存在しなければ作成しておく
            try? fm.createDirectory(at: docs, withIntermediateDirectories: true)
        }
        return docs
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
        ZStack {
            // ドロップ領域
            Color(NSColor.windowBackgroundColor)
                .ignoresSafeArea()
            
            VStack {
                Spacer()
                Text("Drop files")
                    .font(.system(size: 24, weight: .regular, design: .default))
                    .foregroundColor(Color.gray)
                Spacer()
            }
            .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers -> Bool in
                handleOnDrop(providers: providers)
            }
        }
        // ダイアログをモーダルで出す
        .sheet(isPresented: $showDialog, onDismiss: {
            // ダイアログ閉じたら初期化
            droppedURLs.removeAll()
            folderName = ""
        }) {
            dialogView
        }
        // 処理結果をアラートで表示
        .alert(isPresented: $showResultAlert) {
            Alert(title: Text("処理結果"),
                  message: Text(resultMessage),
                  dismissButton: .default(Text("OK")) {
                      // OK 押下でダイアログを閉じる
                  })
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
                    .onChange(of: folderName) { _ in
                        // フォルダ名変更でバリデーション強化もここで行える
                    }
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
        // ドロップされたアイテム (ファイルURL) を全て取得する
        var found = false
        let dispatchGroup = DispatchGroup()
        var tempURLs: [URL] = []
        
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                dispatchGroup.enter()
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { (item, error) in
                    defer { dispatchGroup.leave() }
                    if let data = item as? Data,
                       let str = String(data: data, encoding: .utf8),
                       let url = URL(string: str) {
                        tempURLs.append(url)
                    }
                    else if let url = item as? URL {
                        tempURLs.append(url)
                    }
                }
                found = true
            }
        }
        
        // 全部終わったら
        dispatchGroup.notify(queue: .main) {
            if !tempURLs.isEmpty {
                self.droppedURLs = tempURLs
                // 最古の追加日を求める
                self.defaultDate = computeEarliestDate(from: tempURLs)
                self.selectedDate = self.defaultDate
                self.showDialog = true
            }
        }
        
        return found
    }
    
    // MARK: - 追加日 (addedToDirectoryDate) or 作成日 or 更新日 から最も古い日付を計算
    private func computeEarliestDate(from urls: [URL]) -> Date {
        let fm = FileManager.default
        var dates: [Date] = []
        
        for url in urls {
            do {
                let res = try url.resourceValues(
                    forKeys: [.addedToDirectoryDateKey,
                              .creationDateKey,
                              .contentModificationDateKey])
                if let added = res.addedToDirectoryDate {
                    dates.append(added)
                } else if let created = res.creationDate {
                    dates.append(created)
                } else if let modified = res.contentModificationDate {
                    dates.append(modified)
                }
            } catch {
                // 取得失敗時は「今日の日付」を追加
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
        
        // 親フォルダを取得
        let parentURL = parentFolderURL
        var targetURL = parentURL.appendingPathComponent(baseFolderName)
        
        // 同名フォルダが既にある場合は "(1)", "(2)" ... を末尾に付与してユニーク化
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
            
            // フォルダのタイムスタンプを変更（作成日・更新日）
            try setTimestamp(on: targetURL, date: selectedDate)
            
            // ドロップされたアイテムをすべて移動
            for srcURL in droppedURLs {
                let destURL = targetURL.appendingPathComponent(srcURL.lastPathComponent)
                do {
                    try fm.moveItem(at: srcURL, to: destURL)
                } catch {
                    moveErrors.append("・'\(srcURL.lastPathComponent)' の移動に失敗: \(error.localizedDescription)")
                }
            }
            
            // 結果メッセージ組み立て
            if moveErrors.isEmpty {
                resultMessage = "すべてのファイルを『\(baseFolderName)』へ移動しました。"
            } else {
                resultMessage = """
                一部ファイルの移動に失敗しました:
                \(moveErrors.joined(separator: "\n"))
                """
            }
        } catch {
            // サブフォルダ作成やタイムスタンプ変更に失敗した場合
            resultMessage = "フォルダ作成／タイムスタンプ変更に失敗: \(error.localizedDescription)"
        }
        
        // アラートを表示
        showResultAlert = true
        // ダイアログを閉じる
        showDialog = false
    }
    
    // MARK: - フォルダのタイムスタンプを変更 (CreationDate & ModificationDate)
    private func setTimestamp(on url: URL, date: Date) throws {
        var resourceValues = URLResourceValues()
        resourceValues.creationDate = date
        resourceValues.contentModificationDate = date
        try url.setResourceValues(resourceValues)
        // アクセス日や最終開封日は、ファイルシステム次第なのでここでは省略。
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
