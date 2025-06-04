#!/usr/bin/swift

import Cocoa

let TARGET_SIZE = NSSize(width: 128, height: 128)

func getFileIcon(for url: URL, size: NSSize) -> NSImage? {
    print("debug: 🔍 \(#function) \(url.path)")
    if FileManager.default.fileExists(atPath: url.path) {
        let wsIcon = NSWorkspace.shared.icon(forFile: url.path)
        if !wsIcon.isTemplate && wsIcon.representations.contains(where: { $0.pixelsWide >= 32 && $0.pixelsHigh >= 32 }) {
            print("✅ NSWorkspace からアイコン取得")
            return resizeImage(image: wsIcon, size: size)
        }
    }
    return nil // アイコン取得失敗
}

// MARK: - Utility Functions
func resizeImage(image: NSImage, size: NSSize) -> NSImage {
    let newImage = NSImage(size: size)
    newImage.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high // 高画質で描画
    image.draw(in: NSRect(origin: .zero, size: size),
               from: NSRect(origin: .zero, size: image.size),
               operation: .sourceOver,
               fraction: 1.0)
    newImage.unlockFocus()
    return newImage
}

/// アイコンをファイルに保存する関数
func saveIcon(_ image: NSImage, for fileURL: URL, suffix: String = "_icon_128.png") {
    guard let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let pngData = bitmap.representation(using: .png, properties: [:]) else {
        print("🚫 PNGデータへの変換に失敗しました。")
        return
    }

    do {
        let desktopURL = try FileManager.default.url(for: .desktopDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        let baseName = fileURL.deletingPathExtension().lastPathComponent
        let outputFileName = baseName + suffix
        
        let outputDirectory = desktopURL.appendingPathComponent("IconScript_Mini_Output")
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true, attributes: nil)
        
        let saveURL = outputDirectory.appendingPathComponent(outputFileName)
        
        try pngData.write(to: saveURL)
        print("💾 アイコンを保存しました: \(saveURL.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))")
    } catch {
        print("🚫 アイコンの保存に失敗: \(error)")
    }
}

func main() {
    guard CommandLine.arguments.count > 1 else {
        let scriptName = URL(fileURLWithPath: CommandLine.arguments[0]).lastPathComponent
        print("使用法: ./\(scriptName) <ファイルパス>")
        print("例: ./\(scriptName) /Applications/Calculator.app")
        return
    }

    let filePathArgument = CommandLine.arguments[1]
    let filePath = (filePathArgument as NSString).expandingTildeInPath // チルダ展開
    let fileURL = URL(fileURLWithPath: filePath)

    print("⚙️ 処理対象: \(filePath)")

    if let icon = getFileIcon(for: fileURL, size: TARGET_SIZE) {
        saveIcon(icon, for: fileURL)
        print("✅ 処理完了。")
    } else {
        print("🚫 最終的に128x128アイコンを取得できませんでした。")
    }
}

main()
