//
//  DropMoverServive.swift
//  DropMover
//
//  Created by しん on 2025/06/06.
//

import Cocoa

/// Info.plist の NSServices/NSMessage で指定したセレクタ名と一致させる
@objc class DropMoverService: NSObject {
	/// Finder のサービスメニューから呼ばれるハンドラ
	/// - pboard: 選択されたファイル一覧が入る NSPasteboard
	/// - userData: Info.plist の NSMenuItem/userData が入る (今回は不要なので無視)
	/// - error: エラー文字列を返すポインタ
	@objc func moveWithDropMover(
		_ pboard: NSPasteboard,
		userData: String?,
		error: AutoreleasingUnsafeMutablePointer<NSString?>
	) -> Bool {
		// 1) ペーストボードからファイルURLを読み取る
		guard
			let items = pboard.readObjects(
				forClasses: [NSURL.self],
				options: nil
			) as? [URL],
			!items.isEmpty
		else {
			error.pointee = "ファイルが見つかりませんでした。" as NSString
			return false
		}

		// 2) DropMover アプリを前面化・起動
		//   ・もし起動していなければ起動される
		//   ・すでに起動済みなら前面に出す
		if let bundleURL = Bundle.main.bundleURL as URL? {
			NSWorkspace.shared.openApplication(
				at: bundleURL,
				configuration: NSWorkspace.OpenConfiguration()
			) { app, err in
				// ここではエラーは無視
			}
		}

		// 3) 通知を送って ContentView 側で既存の「アイコンドロップ時と同じロジック」を呼び出す
		DispatchQueue.main.async {
			NotificationCenter.default.post(
				name: .didReceiveFilesOnIcon,
				object: nil,
				userInfo: ["urls": items]
			)
		}

		return true
	}
}
