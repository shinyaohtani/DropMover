#!/usr/bin/swift

import Cocoa // NSWorkspace, NSImage など AppKit の機能を利用
import UniformTypeIdentifiers // UTType を利用 (macOS 11+)
import QuickLookThumbnailing // QLThumbnailGenerator を利用 (macOS 10.15+)

// MARK: - アイコン取得ロジック (FileIconProviderImproved)

enum FileIconProviderImproved {

    static func getDocumentIcon(for url: URL, desiredSize: CGFloat = 128) -> NSImage {
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("🚫 ファイルが存在しません: \(url.path)")
            return dummyIcon(forExt: url.pathExtension.isEmpty ? "???" : url.pathExtension, size: desiredSize)
        }

        print("\n🔎 FileIconProviderImproved.getDocumentIcon 処理開始: \(url.lastPathComponent)")

        // ❶ NSWorkspace.shared.icon(forFile:) を最優先
        let directIcon = NSWorkspace.shared.icon(forFile: url.path)
        print("  - NSWorkspace.icon(forFile:) 結果: size=\(directIcon.size), isTemplate=\(directIcon.isTemplate)")
        if !directIcon.isTemplate && directIcon.representations.contains(where: { $0.pixelsWide > 32 && $0.pixelsHigh > 32 }) {
            print("  ✅ NSWorkspace.icon(forFile:) から有効なアイコンを取得しました。")
            return resizeImage(image: directIcon, targetSize: NSSize(width: desiredSize, height: desiredSize))
        } else {
            print("  ⚠️ NSWorkspace.icon(forFile:) は期待するアイコンではないか、テンプレートです。")
        }

        // ❷ QuickLook .icon
        if let qlIconImg = quickLookImage(url: url, size: desiredSize, requestedTypes: .icon) {
            print("  ✅ QuickLook (.icon) からアイコンを取得しました。")
            return resizeImage(image: qlIconImg, targetSize: NSSize(width: desiredSize, height: desiredSize))
        }

        // ❸ QuickLook .thumbnail (主に画像/PDF用)
        if let qlThumbnailImg = quickLookImage(url: url, size: desiredSize, requestedTypes: .thumbnail) {
            print("  ✅ QuickLook (.thumbnail) からアイコンを取得しました。")
            return resizeImage(image: qlThumbnailImg, targetSize: NSSize(width: desiredSize, height: desiredSize))
        }

        // ❹ UTTypeベースのアイコン
        let ext = url.pathExtension.isEmpty ? "generic" : url.pathExtension
        if let utType = UTType(filenameExtension: ext) ?? UTType(tag: ext, tagClass: .filenameExtension, conformingTo: nil) {
            let typeIcon: NSImage
            if #available(macOS 12.0, *) {
                typeIcon = NSWorkspace.shared.icon(for: utType)
            } else {
                typeIcon = NSWorkspace.shared.icon(forFileType: utType.identifier)
            }
            print("  - UTType (\(utType.identifier)) ベースのアイコン結果: size=\(typeIcon.size), isTemplate=\(typeIcon.isTemplate)")
            if !typeIcon.isTemplate || typeIcon.representations.contains(where: { $0.pixelsWide > 32 }) {
                 print("  ✅ UTType ベースのアイコンを取得しました。")
                 return resizeImage(image: typeIcon, targetSize: NSSize(width: desiredSize, height: desiredSize))
            }
        }

        print("  🚫 全ての取得方法で失敗。ダミーアイコンを返します。")
        return dummyIcon(forExt: ext.uppercased(), size: desiredSize)
    }

    private static func quickLookImage(url: URL, size: CGFloat, requestedTypes: QLThumbnailGenerator.Request.RepresentationTypes) -> NSImage? {
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: size, height: size),
            scale: NSScreen.main?.backingScaleFactor ?? 2.0,
            representationTypes: requestedTypes
        )

        var resultImage: NSImage?
        let semaphore = DispatchSemaphore(value: 0)

        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { thumbnail, error in
            if let thumbnail = thumbnail {
                switch thumbnail.type {
                case .icon, .thumbnail, .lowQualityThumbnail:
                    // Assuming compiler is correct and these are non-optional for these types
                    let nsImg = thumbnail.nsImage // Direct access
                    if nsImg.size.width > 0 && nsImg.size.height > 0 {
                        resultImage = nsImg
                    } else {
                        let cgImg = thumbnail.cgImage // Direct access
                        // It's good practice to check if cgImg is valid even if non-optional,
                        // e.g., width and height > 0, but for now, let's follow the compiler.
                        resultImage = NSImage(cgImage: cgImg, size: NSSize(width: cgImg.width, height: cgImg.height))
                    }
                /*
                case .imageFile: // サムネイルが画像ファイルとして返される場合
                    if let imageURL = thumbnail.imageFileURL {
                         print("  ℹ️ QuickLook: 画像ファイルパスとしてサムネイルを受信: \(imageURL.path)")
                         resultImage = NSImage(contentsOf: imageURL)
                    } else {
                        print("  ⚠️ QuickLook: .imageFile タイプで画像ファイルURLがnilです (\(url.lastPathComponent))")
                    }
                */
                /*
                case .pdf:
                    print("  ℹ️ QuickLook: PDF表現を受信しました（画像化は行いません） (\(url.lastPathComponent))")
                */
                @unknown default:
                    print("  ⚠️ QuickLook: 未知の表現タイプ \(thumbnail.type.rawValue) を受信しました (\(url.lastPathComponent))。cgImage/nsImage の取得を試みます。")
                    // Fallback for unknown types if compiler implies nsImage/cgImage might still be non-optional
                    // This is speculative.
                    let nsImg = thumbnail.nsImage
                    if nsImg.size.width > 0 && nsImg.size.height > 0 {
                        resultImage = nsImg
                    } else {
                         let cgImg = thumbnail.cgImage
                         if cgImg.width > 0 && cgImg.height > 0 { // Basic check for CGImage validity
                            resultImage = NSImage(cgImage: cgImg, size: NSSize(width: cgImg.width, height: cgImg.height))
                         } else {
                            print("  ⚠️ QuickLook: @unknown default でも有効な画像が見つかりませんでした。")
                         }
                    }
                }
            } else if let error = error {
                let typeString = requestedTypes == .icon ? ".icon" : (requestedTypes == .thumbnail ? ".thumbnail" : "\(requestedTypes)")
                print("  ⚠️ QuickLook エラー (\(typeString)): \(error.localizedDescription) for \(url.lastPathComponent)")
            }
            semaphore.signal()
        }

        if semaphore.wait(timeout: .now() + .seconds(2)) == .timedOut {
            let typeString = requestedTypes == .icon ? ".icon" : (requestedTypes == .thumbnail ? ".thumbnail" : "\(requestedTypes)")
            print("  ⚠️ QuickLook タイムアウト (\(typeString)) for \(url.lastPathComponent)")
            return nil
        }
        return resultImage
    }

    private static func dummyIcon(forExt ext: String, size: CGFloat) -> NSImage {
        let img = NSImage(size: NSSize(width: size, height: size))
        img.lockFocus()
        NSColor.windowBackgroundColor.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: img.size)).fill()
        NSColor.gray.setStroke()
        NSBezierPath(rect: NSRect(origin: .zero, size: img.size)).stroke()

        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.secondaryLabelColor,
            .font: NSFont.systemFont(ofSize: size * 0.3, weight: .medium)
        ]
        let str = NSString(string: ext.count > 4 ? String(ext.prefix(3))+"…" : ext)
        let strSize = str.size(withAttributes: attrs)
        let rect = NSRect(x: (size - strSize.width) / 2,
                          y: (size - strSize.height) / 2,
                          width: strSize.width,
                          height: strSize.height)
        str.draw(in: rect, withAttributes: attrs)
        img.unlockFocus()
        return img
    }

    private static func resizeImage(image: NSImage, targetSize: NSSize) -> NSImage {
        let newImage = NSImage(size: targetSize)
        newImage.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(origin: .zero, size: targetSize),
                   from: NSRect(origin: .zero, size: image.size),
                   operation: .sourceOver,
                   fraction: 1.0)
        newImage.unlockFocus()
        return newImage
    }
}

// MARK: - アイコン詳細検査関数 (変更なし)
func inspectFileIcon(for fileURL: URL) -> NSImage? {
    guard fileURL.isFileURL else {
        print("🚫 \(fileURL) はファイルURLではありません。")
        return nil
    }
    let filePath = fileURL.path
    print("\n🕵️ inspectFileIcon 処理開始: \(fileURL.lastPathComponent)")

    guard FileManager.default.fileExists(atPath: filePath) else {
        print("🚫 ファイルが存在しません: \(filePath)")
        return nil
    }

    let icon = NSWorkspace.shared.icon(forFile: filePath)
    print("  - NSImage サイズ: \(icon.size)")
    print("  - isTemplate: \(icon.isTemplate)")
    print("  - リプレゼンテーション数: \(icon.representations.count)")
    if icon.representations.isEmpty {
        print("  ⚠️ リプレゼンテーションがありません。")
    }
    for (index, rep) in icon.representations.enumerated() {
        print("    Rep \(index): \(rep.className), ピクセルサイズ: \(NSSize(width: rep.pixelsWide, height: rep.pixelsHigh)), ポイントサイズ: \(rep.size)")
    }

    let debugFileName = fileURL.deletingPathExtension().lastPathComponent + "_inspected_icon.png"
    saveIconForDebug(icon, fileName: debugFileName)

    return icon
}

// MARK: - デバッグ用アイコン保存関数 (変更なし)
func saveIconForDebug(_ image: NSImage, fileName: String) {
    guard let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let pngData = bitmap.representation(using: .png, properties: [:]) else {
        print("🚫 アイコンのPNGデータへの変換に失敗: \(fileName)")
        return
    }

    do {
        let desktopURL = try FileManager.default.url(for: .desktopDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        let sanitizedFileName = fileName.replacingOccurrences(of: "/", with: "-")
        let saveURL = desktopURL.appendingPathComponent("IconScript_Output").appendingPathComponent(sanitizedFileName)

        try FileManager.default.createDirectory(at: saveURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)

        try pngData.write(to: saveURL)
        print("  💾 デバッグ用アイコンを保存しました: \(saveURL.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))")
    } catch {
        print("🚫 アイコンの保存に失敗: \(error) - \(fileName)")
    }
}

// MARK: - メイン処理 (変更なし)
func main() {
    guard CommandLine.arguments.count > 1 else {
        let scriptName = URL(fileURLWithPath: CommandLine.arguments[0]).lastPathComponent
        print("使用法: ./\(scriptName) <ファイルパス>")
        print("例: ./\(scriptName) /Applications/Calculator.app")
        print("例: ./\(scriptName) ~/Desktop/MyDocument.txt")
        return
    }

    let filePathArgument = CommandLine.arguments[1]
    let filePath = (filePathArgument as NSString).expandingTildeInPath
    let fileURL = URL(fileURLWithPath: filePath)

    print("======================================================")
    print("アイコン取得実験スクリプト: \(fileURL.path)")
    print("======================================================")

    _ = inspectFileIcon(for: fileURL)

    let desiredSize: CGFloat = 128
    print("\n🎨 FileIconProviderImproved.getDocumentIcon (サイズ: \(Int(desiredSize))x\(Int(desiredSize))) 処理開始...")
    let iconFromProvider = FileIconProviderImproved.getDocumentIcon(for: fileURL, desiredSize: desiredSize)

    let providerFileName = fileURL.deletingPathExtension().lastPathComponent + "_provider_\(Int(desiredSize))px_icon.png"
    saveIconForDebug(iconFromProvider, fileName: providerFileName)

    print("\n======================================================")
    print("処理完了。デスクトップの 'IconScript_Output' フォルダを確認してください。")
    print("======================================================")
}

// MARK: - スクリプト実行
main()