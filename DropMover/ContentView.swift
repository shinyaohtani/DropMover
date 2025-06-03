//
//  DropMoverRefactored.swift
//  DropMover
//
//  Refactored on 2025/06/03
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Model

struct DropContext: Identifiable {
    let id = UUID()
    let urls: [URL]
    let defaultDate: Date
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
}

// MARK: - Main View

struct ContentView: View {
    // UI State
    @State private var dropContext: DropContext?
    @State private var showResultAlert = false
    @State private var resultMessage = ""

    private let folderLocator = ParentFolderLocator()

    // Body (<25 lines)
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                background(for: proxy)
                dropOverlay
                promptText
            }
            .overlay(alignment: .bottomTrailing) {
                openFolderButton
                    .padding(12)
            }
            .sheet(
                item: $dropContext,
                onDismiss: {
                    dropContext = nil
                }
            ) { context in
                SheetView(
                    initialDate: context.defaultDate,
                    droppedURLs: context.urls,
                    parentFolderURL: parentFolder(),
                    onFinish: { message in
                        resultMessage = message
                        showResultAlert = true
                    }
                )
            }
            .alert("DropMover", isPresented: $showResultAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(resultMessage)
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: .didReceiveFilesOnIcon
                )
            ) { note in
                guard let urls = note.userInfo?["urls"] as? [URL] else {
                    return
                }
                presentSheet(with: urls)
            }
        }
    }

    // MARK: - Public helpers

    private func handleOnDrop(providers: [NSItemProvider]) -> Bool {
        var urls: [URL] = []
        let group = DispatchGroup()

        providers.forEach { provider in
            guard
                provider.hasItemConformingToTypeIdentifier(
                    UTType.fileURL.identifier
                )
            else { return }
            group.enter()
            provider.loadItem(
                forTypeIdentifier: UTType.fileURL.identifier,
                options: nil
            ) { item, _ in
                if let url = FileDropHelper.url(from: item) { urls.append(url) }
                group.leave()
            }
        }

        group.notify(queue: .main) { presentSheet(with: urls) }
        return true
    }

    private func presentSheet(with urls: [URL]) {
        guard !urls.isEmpty else { return }
        dropContext = DropContext(
            urls: urls,
            defaultDate: FileDropHelper.earliestDate(in: urls)
        )
    }

    private func parentFolder() -> URL { folderLocator.url() }

    // MARK: - UI fragments (private)
    private var openFolderButton: some View {
        Button {
            // 変更点: 保存されたフォルダがあれば選択状態で開く
            if let last = LastFolderStore.load(),
                FileManager.default.fileExists(atPath: last.path)
            {
                NSWorkspace.shared.activateFileViewerSelecting([last])
            } else {
                NSWorkspace.shared.open(parentFolder())
            }
        } label: {
            Image(systemName: "folder")
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(.white)
                .padding(6)
                .background(.thinMaterial, in: Circle())  // 半透明円形
        }
        .buttonStyle(.plain)
        .help("移動先フォルダを Finder で開く")
    }

    private func background(for proxy: GeometryProxy) -> some View {
        Image("black-whole")
            .resizable()
            .scaledToFill()
            .frame(width: proxy.size.width, height: proxy.size.height)
            .ignoresSafeArea()
    }

    private var dropOverlay: some View {
        Color.clear
            .contentShape(Rectangle())
            .onDrop(
                of: [UTType.fileURL],
                isTargeted: nil,
                perform: handleOnDrop
            )
    }

    private var promptText: some View {
        VStack {
            Spacer()
            Text("Drop files")
                .font(.system(size: 24))
                .foregroundColor(.gray)
                .offset(y: -20)
            Spacer()
        }
    }
}

// MARK: - Sheet View

struct SheetView: View {
    @Environment(\.dismiss) private var dismiss

    let initialDate: Date
    let droppedURLs: [URL]
    let parentFolderURL: URL
    let onFinish: (String) -> Void

    @State private var selectedDate: Date
    @State private var folderName = ""

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
        _selectedDate = State(initialValue: initialDate)
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
        let (targetURL, baseName) = makeUniqueFolder()
        var errors: [String] = []
        moveFiles(to: targetURL, errors: &errors)
        LastFolderStore.save(targetURL)
        let message = resultMessage(baseName: baseName, errors: errors)
        onFinish(message)
        dismiss()
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

        for src in droppedURLs {
            let dest = targetURL.appendingPathComponent(src.lastPathComponent)
            do { try fm.moveItem(at: src, to: dest) } catch {
                errors.append(
                    "・'\(src.lastPathComponent)' の移動に失敗: \(error.localizedDescription)"
                )
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

    private func resultMessage(baseName: String, errors: [String]) -> String {
        errors.isEmpty
            ? "「\(baseName)」\nに移動しました。"
            : "一部ファイルの移動に失敗しました:\n" + errors.joined(separator: "\n")
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View { ContentView() }
}
