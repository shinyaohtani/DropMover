//
//  FinderSync.swift
//  DropMoverFinderExtension
//
//  Finder拡張機能 - 右クリックメニューから「DropMoverで移動...」を提供
//

import Cocoa
import FinderSync

class FinderSync: FIFinderSync {

    override init() {
        super.init()

        // 全てのボリュームを監視対象にする
        // これにより、どのフォルダでも右クリックメニューが表示される
        FIFinderSyncController.default().directoryURLs = Set([URL(fileURLWithPath: "/")])
    }

    // MARK: - Menu and toolbar item support

    override var toolbarItemName: String {
        return "DropMover"
    }

    override var toolbarItemToolTip: String {
        return "選択したファイルをDropMoverで移動"
    }

    override var toolbarItemImage: NSImage {
        return NSImage(named: NSImage.folderName) ?? NSImage()
    }

    /// Finderの右クリックメニューに項目を追加
    override func menu(for menuKind: FIMenuKind) -> NSMenu {
        let menu = NSMenu(title: "")

        switch menuKind {
        case .contextualMenuForItems:
            // ファイル/フォルダを選択した状態での右クリック
            let menuItem = NSMenuItem(
                title: "DropMoverで移動...",
                action: #selector(moveWithDropMover(_:)),
                keyEquivalent: ""
            )
            menuItem.image = NSImage(named: NSImage.folderName)
            menu.addItem(menuItem)

        case .toolbarItemMenu:
            // ツールバーからのメニュー
            let menuItem = NSMenuItem(
                title: "DropMoverで移動...",
                action: #selector(moveWithDropMover(_:)),
                keyEquivalent: ""
            )
            menu.addItem(menuItem)

        default:
            break
        }

        return menu
    }

    /// メニュー項目が選択されたときの処理
    @objc func moveWithDropMover(_ sender: AnyObject?) {
        // 選択されているファイル/フォルダのURLを取得
        guard let targetURLs = FIFinderSyncController.default().selectedItemURLs(),
              !targetURLs.isEmpty else {
            return
        }

        // URLスキームでDropMover.appを起動
        openDropMoverWithURLScheme(targetURLs)
    }

    /// URLスキームを使ってDropMover.appを起動し、ファイルパスを渡す
    private func openDropMoverWithURLScheme(_ urls: [URL]) {
        // dropmover://move?file=path1&file=path2 形式のURLを構築
        var components = URLComponents()
        components.scheme = "dropmover"
        components.host = "move"

        // 各ファイルパスをクエリパラメータとして追加
        components.queryItems = urls.map { url in
            URLQueryItem(name: "file", value: url.path)
        }

        guard let schemeURL = components.url else {
            NSLog("DropMover: URLスキームの構築に失敗")
            return
        }

        // URLスキームを開く
        NSWorkspace.shared.open(schemeURL)
    }
}
