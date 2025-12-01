//
//  DropMoverRefactored.swift
//  DropMover
//
//  Refactored on 2025/06/03
//

import AppKit
import Cocoa
import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers

/// Finder とほぼ同じ優先度で **128×128 カラー** の書類アイコンを返す
enum FileIconProviderImproved {
    
    static func icon(for url: URL, size: CGFloat) -> NSImage {
        
        //------------------------------------------------------------------//
        // ❶ NSWorkspace.icon(forFile:)  ─ カスタム or アプリ提供アイコン
        //------------------------------------------------------------------//
        print("🔍 NSWorkspace からアイコン取得: \(url.path)")
        let wsIcon = NSWorkspace.shared.icon(forFile: url.path)
        if !wsIcon.isTemplate
            && wsIcon.representations.contains(where: {
                $0.pixelsWide >= 32
            })
        {
            print("✅ NSWorkspace からアイコン取得")
            return wsIcon.resized(to: size)
        } else {
            print("❌ NSWorkspace からの取得に失敗: \(url.path)")
        }
        
        //------------------------------------------------------------------//
        // ❷ QuickLook (.icon)  → ❸ QuickLook (.thumbnail)
        //------------------------------------------------------------------//
        for rep in [
            QLThumbnailGenerator.Request.RepresentationTypes.icon,
            .thumbnail,
        ] {
            if let qlImg = quickLook(url, rep: rep, edge: size) {
                print("✅ QuickLook (.icon) からアイコン取得")
                return qlImg
            }
        }
        
        //------------------------------------------------------------------//
        // ❹ UTType 由来の書類アイコン
        //------------------------------------------------------------------//
        if let ut = UTType(filenameExtension: url.pathExtension) {
            let img: NSImage
            if #available(macOS 13, *) {
                img = NSWorkspace.shared.icon(for: ut)
            } else {
                img = NSWorkspace.shared.icon(for: ut)
            }
            if !img.isTemplate { return img.resized(to: size) }
        }
        
        //------------------------------------------------------------------//
        // ❺ フォールバック：拡張子文字入りダミー
        //------------------------------------------------------------------//
        print("✅ フォールバック：拡張子文字入りダミー")
        return dummyIcon(ext: url.pathExtension, edge: size)
    }
    
    // MARK: - QuickLook 同期ヘルパ
    private static func quickLook(
        _ url: URL,
        rep: QLThumbnailGenerator.Request.RepresentationTypes,
        edge: CGFloat
    ) -> NSImage? {
        let req = QLThumbnailGenerator.Request(
            fileAt: url,
            size: .init(width: edge, height: edge),
            scale: 2,
            representationTypes: rep
        )
        let sema = DispatchSemaphore(value: 0)
        var out: NSImage?
        QLThumbnailGenerator.shared.generateBestRepresentation(for: req) {
            r,
            _ in
            if let cg = r?.cgImage {
                out = NSImage(cgImage: cg, size: .zero).resized(to: edge)
            }
            sema.signal()
        }
        sema.wait()
        return out
    }
    
    // MARK: - ダミー生成
    private static func dummyIcon(ext: String, edge: CGFloat) -> NSImage {
        let img = NSImage(size: .init(width: edge, height: edge))
        img.lockFocus()
        NSColor.windowBackgroundColor.setFill()
        NSBezierPath(rect: .init(origin: .zero, size: img.size)).fill()
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: edge * 0.32, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        let label = ext.isEmpty ? "?" : ext.uppercased().prefix(4)
        let ns = NSString(string: String(label))
        let sz = ns.size(withAttributes: attrs)
        ns.draw(
            at: .init(x: (edge - sz.width) / 2, y: (edge - sz.height) / 2),
            withAttributes: attrs
        )
        img.unlockFocus()
        return img
    }
}

// MARK: - NSImage resize helper
extension NSImage {
    fileprivate func resized(to edge: CGFloat) -> NSImage {
        let dst = NSImage(size: .init(width: edge, height: edge))
        dst.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        draw(
            in: .init(origin: .zero, size: dst.size),
            from: .init(origin: .zero, size: size),
            operation: .sourceOver,
            fraction: 1
        )
        dst.unlockFocus()
        return dst
    }
}

// MARK: - Model

// MARK: - DropContext  (dropPoint を追加し Equatable でシート判定)
struct DropContext: Identifiable, Equatable {
    let id = UUID()
    let urls: [URL]
    let defaultDate: Date
    let dropPoint: CGPoint  // 左下原点(0,0)
    let suggestedFolderName: String
}

// MARK: - Helpers
private struct ParentFolderLocator {
    @AppStorage("parentFolderPath") private var parentPath: String = ""
    
    // public
    func url() -> URL {
        let fm = FileManager.default
        let cleaned = cleanPath(parentPath)
        let destination = cleaned.flatMap(expandedPath) ?? defaultURL()
        ensureDirectory(destination, with: fm)
        return destination
    }
    
    // MARK: - private
    
    private func cleanPath(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
    
    private func expandedPath(_ raw: String) -> URL {
        let expanded = (raw as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expanded, isDirectory: true)
    }
    
    private func ensureDirectory(_ url: URL, with fm: FileManager) {
        if !fm.fileExists(atPath: url.path) {
            try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }
    
    private func defaultURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents")
            .appendingPathComponent("DropMover")
    }
}

private enum LastFolderStore {
    private static let key = "lastCreatedFolderPath"
    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
    static func save(_ url: URL) {
        UserDefaults.standard.set(url.path, forKey: key)
    }
    static func load() -> URL? {
        guard let path = UserDefaults.standard.string(forKey: key) else {
            return nil
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }
}

private enum FileDropHelper {
    /// Convert the `item` returned from NSItemProvider to URL if possible
    static func url(from item: NSSecureCoding?) -> URL? {
        if let data = item as? Data,
           let str = String(data: data, encoding: .utf8)
        {
            return URL(string: str)
        }
        return item as? URL
    }
    
    /// Return the oldest timestamp among added / modified dates of given urls
    static func earliestDate(in urls: [URL]) -> Date {
        urls.compactMap { url in
            (try? url.resourceValues(forKeys: [
                .addedToDirectoryDateKey, .contentModificationDateKey,
            ])).flatMap { v in
                [v.addedToDirectoryDate, v.contentModificationDate].compactMap {
                    $0
                }.min()
            }
        }.min() ?? Date()
    }
    
    static func suggestedFolderName(for urls: [URL]) -> String {
        let bases = urls.map { $0.deletingPathExtension().lastPathComponent }
        guard let first = bases.first else { return "" }
        guard bases.count > 1 else { return first }
        
        var prefix = first
        for s in bases.dropFirst() {
            prefix = prefix.commonPrefix(with: s) // 大文字小文字はそのまま
            if prefix.isEmpty { break }
        }
        return prefix.isEmpty ? first : prefix
    }
}

// MARK: - Main View

//
//  ContentView.swift  (2025-06-xx final)
//  DropMover
//

// MARK: - ContentView
struct ContentView: View {
    
    // ── UI State ──────────────────────────────────────────
    @State private var dropContext: DropContext? = nil
    @State private var showResultAlert = false
    @State private var resultMessage = ""
    @State private var blastModel: IconBlastModel? = nil
    
    let iconSize: CGFloat = 128
    
    // 親フォルダの計算ロジック（以前と同じ）
    @AppStorage("parentFolderPath") private var parentFolderPath: String = ""
    private var parentFolderURL: URL {
        let fm = FileManager.default
        let trimmed = parentFolderPath.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let url: URL =
        trimmed.isEmpty
        ? fm.homeDirectoryForCurrentUser.appendingPathComponent(
            "Documents/DropMover"
        )
        : URL(
            fileURLWithPath: (trimmed as NSString).expandingTildeInPath,
            isDirectory: true
        )
        if !fm.fileExists(atPath: url.path) {
            try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }
    
    // ── View body ─────────────────────────────────────────
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                // 背景
                Image("black-whole")
                    .resizable().scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .ignoresSafeArea()
                
                // ドロップ受付オーバーレイ
                Color.clear
                    .contentShape(Rectangle())
                    .onDrop(of: [UTType.fileURL], isTargeted: nil) {
                        providers,
                        loc in
                        return handleOnDrop(
                            providers: providers,
                            dropPoint: loc
                        )
                    }
                
                // 中央テキスト
                VStack {
                    Spacer()
                    Text("Drop files")
                        .font(.system(size: 24))
                        .foregroundColor(.gray)
                        .offset(y: -20)
                    Spacer()
                }
                
                // 吸い込みアニメ
                IconBlastView(model: $blastModel)
            }
#if DEBUG
            .overlay(alignment: .bottomLeading) {  // ← 左下に配置
                Button {
                    let dummy = NSWorkspace.shared.icon(for: .plainText)
                    blastModel = IconBlastModel(
                        icons: Array(repeating: dummy, count: 15),
                        dropPoint: CGPoint(x: 180, y: 136),  // 左下が(0,0)
                        isize: iconSize
                    )
                    print("Debug Animation triggered")
                } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                        .padding(6)
                        .background(.thinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .help("アニメーションをテスト再生")
                .padding(12)
            }
#endif
            .overlay(alignment: .bottomTrailing) {
                openFolderButton.padding(12)
            }
            // --- シート ---
            .sheet(item: $dropContext, onDismiss: { dropContext = nil }) { ctx in
                SheetView(
                    initialDate: ctx.defaultDate,
                    droppedURLs: ctx.urls,
                    parentFolderURL: parentFolderURL,
                    dropPoint: ctx.dropPoint,
                    blastModel: $blastModel,
                    iconSize: iconSize,
                    initialFolderName: ctx.suggestedFolderName
                ) { msg in
                    if !msg.isEmpty {
                        resultMessage = msg
                        showResultAlert = true
                    }
                }
            }
            // --- 失敗時のみダイアログ ---
            .alert("DropMover", isPresented: $showResultAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(resultMessage)
            }
            // Dock / Finder へドロップされたとき
            .onReceive(NotificationCenter.default.publisher(for: .didReceiveFilesOnIcon)) { note in
                guard let urls = note.userInfo?["urls"] as? [URL] else { return }
                let ctx = DropContext(
                    urls: urls,
                    defaultDate: FileDropHelper.earliestDate(in: urls),
                    dropPoint: CGPoint(x: 180, y: 120),
                    suggestedFolderName: FileDropHelper.suggestedFolderName(for: urls)
                )
                dropContext = ctx
            }
        }
    }
    
    // ── open-folder button ───────────────────────────────
    private var openFolderButton: some View {
        Button {
            let currentParent = parentFolderURL.standardizedFileURL
            if let last = LastFolderStore.load(),
               FileManager.default.fileExists(atPath: last.path),
               last.deletingLastPathComponent().standardizedFileURL
                == currentParent
            {
                NSWorkspace.shared.activateFileViewerSelecting([last])
            } else {
                LastFolderStore.clear()
                NSWorkspace.shared.open(currentParent)
            }
        } label: {
            Image(systemName: "folder")
                .font(.system(size: 14))
                .foregroundColor(.white)
                .padding(6)
                .background(.thinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .help("移動先フォルダを Finder で開く")
    }
    
    // ── ドロップ処理 ────────────────────────────────────
    private func handleOnDrop(
        providers: [NSItemProvider],
        dropPoint: CGPoint
    ) -> Bool {
        // スレッドセーフなアクセスのためにクラスを使用
        let collector = URLCollector(count: providers.count)
        let group = DispatchGroup()

        for (i, p) in providers.enumerated()
        where p.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            group.enter()
            p.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                if let u = FileDropHelper.url(from: item) {
                    collector.set(url: u, at: i)
                }
            }
        }

        group.notify(queue: .main) {
            let urls = collector.urls()
            guard !urls.isEmpty else { return }
            dropContext = DropContext(
                urls: urls,
                defaultDate: FileDropHelper.earliestDate(in: urls),
                dropPoint: dropPoint,
                suggestedFolderName: FileDropHelper.suggestedFolderName(for: urls)
            )
        }
        return true
    }
}

// MARK: - Thread-safe URL Collector
/// 複数スレッドから安全にURLを収集するためのクラス
private class URLCollector {
    private var slots: [URL?]
    private let lock = NSLock()

    init(count: Int) {
        self.slots = Array(repeating: nil, count: count)
    }

    func set(url: URL, at index: Int) {
        lock.lock()
        defer { lock.unlock() }
        slots[index] = url
    }

    func urls() -> [URL] {
        lock.lock()
        defer { lock.unlock() }
        return slots.compactMap { $0 }
    }
}

// MARK: - Sheet View

struct SheetView: View {
    @Environment(\.dismiss) private var dismiss
    
    let initialDate: Date
    let droppedURLs: [URL]
    let parentFolderURL: URL
    let onFinish: (String) -> Void
    let dropPoint: CGPoint
    let iconSize: CGFloat
    @Binding var blastModel: IconBlastModel?
    
    @State private var selectedDate: Date
    @State private var folderName = ""
    
    init(
        initialDate: Date,
        droppedURLs: [URL],
        parentFolderURL: URL,
        dropPoint: CGPoint,
        blastModel: Binding<IconBlastModel?>,
        iconSize: CGFloat,
        initialFolderName: String,
        onFinish: @escaping (String) -> Void
    ) {
        self.initialDate = initialDate
        self.droppedURLs = droppedURLs
        self.parentFolderURL = parentFolderURL
        self.dropPoint = dropPoint
        self._blastModel = blastModel
        self.iconSize = iconSize
        self.onFinish = onFinish
        _selectedDate = State(initialValue: initialDate)
        _folderName   = State(initialValue: initialFolderName)
    }
    
    private let formatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = .init(identifier: .gregorian)
        f.locale = .init(identifier: "ja_JP")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    
    private var previewFolderName: String {
        "\(formatter.string(from: selectedDate)) \(folderName)"
    }
    
    // Body (<25 lines)
    var body: some View {
        VStack(spacing: 16) {
            header
            datePicker
            folderInput
            preview
            Divider()
            actionButtons
        }
        .padding(20)
        .frame(width: 400)
    }
    
    // MARK: - UI fragments
    
    private var header: some View {
        Text("フォルダを作成してファイルを移動").font(.headline)
    }
    
    private var datePicker: some View {
        DatePicker(
            "日付を選択:",
            selection: $selectedDate,
            displayedComponents: .date
        )
        .datePickerStyle(.graphical)
        .frame(maxHeight: 250)
    }
    
    private var folderInput: some View {
        HStack {
            Text("フォルダ名:")
            TextField("フォルダ名を入力してください", text: $folderName)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    if !folderName.trimmingCharacters(in: .whitespaces).isEmpty {
                        performMove()
                    }
                }
        }
    }
    
    private var preview: some View {
        HStack {
            Spacer()
            Text("生成フォルダ名: ")
            Text(previewFolderName)
                .foregroundColor(folderName.isEmpty ? .gray : .primary)
            Spacer()
        }
        .font(.system(size: 14, weight: .light, design: .monospaced))
    }
    
    private var actionButtons: some View {
        HStack {
            Button("キャンセル") { dismiss() }
            Spacer()
            Button("移動する", action: performMove)
                .disabled(
                    folderName.trimmingCharacters(in: .whitespaces).isEmpty
                )
        }
    }
    
    // MARK: - Move Logic (public)
    
    private func performMove() {
        // アイコン取得して保持（15 枚まで）
        let cachedIcons: [NSImage] =
        droppedURLs.prefix(15).map {
            FileIconProviderImproved.icon(for: $0, size: iconSize)
        }
        
        // フォルダ作成・ファイル移動
        let (targetURL, baseName) = makeUniqueFolder()
        var errors: [String] = []
        moveFiles(to: targetURL, errors: &errors)
        LastFolderStore.save(targetURL)
        if errors.isEmpty {
            dismiss()
            blastModel = IconBlastModel(
                icons: cachedIcons,
                dropPoint: dropPoint,
                isize: iconSize
            )
            onFinish("")
        } else {
            let msg = resultMessage(baseName: baseName, errors: errors)
            dismiss()
            onFinish(msg)
        }
    }
    
    // MARK: - Helpers (private)
    private func makeUniqueFolder() -> (URL, String) {
        let fm = FileManager.default
        let dateStr = formatter.string(from: selectedDate)
        var baseName = "\(dateStr) \(folderName)"
        var target = parentFolderURL.appendingPathComponent(baseName)
        var suffix = 1
        
        while fm.fileExists(atPath: target.path) {
            suffix += 1
            baseName = "\(dateStr) \(folderName) (\(suffix))"
            target = parentFolderURL.appendingPathComponent(baseName)
        }
        try? fm.createDirectory(at: target, withIntermediateDirectories: true)
        return (target, baseName)
    }
    
    private func moveFiles(to targetURL: URL, errors: inout [String]) {
        let fm = FileManager.default
        // 同じ名前のファイルが複数ある場合の競合を追跡
        var usedNames: Set<String> = []

        for src in droppedURLs {
            let originalName = src.lastPathComponent
            let dest = uniqueDestination(
                for: originalName,
                in: targetURL,
                usedNames: &usedNames
            )
            do {
                try fm.moveItem(at: src, to: dest)
                // 成功したら使用済み名前に追加
                usedNames.insert(dest.lastPathComponent)
            } catch {
                errors.append("・'\(originalName)' の移動に失敗: \(error.localizedDescription)")
            }
        }

        do {
            var rv = URLResourceValues()
            rv.creationDate = selectedDate
            rv.contentModificationDate = selectedDate
            var mutable = targetURL
            try mutable.setResourceValues(rv)
        } catch {
            errors.append("・フォルダのタイムスタンプ変更に失敗: \(error.localizedDescription)")
        }
    }

    /// ファイル名の重複を避けてユニークな宛先URLを返す
    /// - Parameters:
    ///   - name: 元のファイル名
    ///   - dir: 移動先ディレクトリ
    ///   - usedNames: 今回のバッチで既に使用された名前のセット（競合回避用）
    private func uniqueDestination(
        for name: String,
        in dir: URL,
        usedNames: inout Set<String>
    ) -> URL {
        let fm = FileManager.default
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension

        var candidateName = name
        var candidate = dir.appendingPathComponent(candidateName)
        var i = 2

        // ファイルシステム上に存在するか、または今回のバッチで使用済みの場合はリネーム
        while fm.fileExists(atPath: candidate.path) || usedNames.contains(candidateName) {
            candidateName = ext.isEmpty ? "\(base) (\(i))" : "\(base) (\(i)).\(ext)"
            candidate = dir.appendingPathComponent(candidateName)
            i += 1
        }

        return candidate
    }
    
    private func resultMessage(baseName: String, errors: [String]) -> String {
        errors.isEmpty
        ? "「\(baseName)」\nに移動しました。"
        : "一部ファイルの移動に失敗しました:\n" + errors.joined(separator: "\n")
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View { ContentView() }
}
