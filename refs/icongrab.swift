#!/usr/bin/env swift
// icongrab.swift ― Drag-&-Drop で得たい Finder アイコンを
// コマンドラインで確認するための簡易ツール。
// macOS 12+ / Swift 5.7 以上で動作。

import Foundation
import AppKit
import QuickLookThumbnailing
import UniformTypeIdentifiers

// MARK: – Helper: 128×128 カラーアイコンを返す
func iconForFile(_ url: URL, size: CGFloat = 128) -> NSImage {
    // 1) カスタムアイコン？
    if (try? url.resourceValues(forKeys: [.hasCustomIconKey]))?.hasCustomIcon == true {
        let img = NSWorkspace.shared.icon(forFile: url.path)
        img.isTemplate = false
        return img.resized(to: size)
    }

    // 2) QuickLook (.thumbnail → .icon)
    for rep in [QLThumbnailGenerator.Request.RepresentationTypes.thumbnail,
                .icon] {
        if let img = quickLook(url, rep: rep, size: size) { return img }
    }

    // 3) Type アイコン
	if let ut = UTType(filenameExtension: url.pathExtension) {
	    let icon: NSImage
	    if #available(macOS 13.0, *) {
	        icon = NSWorkspace.shared.icon(for: ut)              // macOS 13+
	    } else {
	        icon = NSWorkspace.shared.icon(forContentType: ut)   // macOS 12
	    }
	    if !icon.isTemplate { return icon.resized(to: size) }
	}
    // 4) fallback: white + ext text
    return dummy(ext: url.pathExtension.uppercased(), size: size)
}

// QuickLook helper
func quickLook(_ url: URL,
               rep: QLThumbnailGenerator.Request.RepresentationTypes,
               size: CGFloat) -> NSImage? {
    let req = QLThumbnailGenerator.Request(fileAt: url,
                                           size: .init(width: size, height: size),
                                           scale: 2,
                                           representationTypes: rep)
    let sema = DispatchSemaphore(value: 0)
    var out: NSImage?
    QLThumbnailGenerator.shared.generateBestRepresentation(for: req) { r,_ in
        if let cg = r?.cgImage { out = NSImage(cgImage: cg, size: .zero) }
        sema.signal()
    }
    sema.wait()
    return out
}

// MARK: – Utilities
extension NSImage {
    func resized(to s: CGFloat) -> NSImage {
        let img = NSImage(size: .init(width: s, height: s))
        img.lockFocus(); draw(in: .init(origin: .zero, size: img.size)); img.unlockFocus()
        return img
    }
}
func dummy(ext: String, size: CGFloat) -> NSImage {
    let img = NSImage(size: .init(width: size, height: size))
    img.lockFocus()
    NSColor.white.set(); NSBezierPath(rect: .init(origin: .zero, size: img.size)).fill()
    let attrs: [NSAttributedString.Key:Any] = [.font:NSFont.boldSystemFont(ofSize:size*0.35),
                                               .foregroundColor:NSColor.systemBlue]
    let str = NSString(string: ext.isEmpty ? "?" : ext)
    let sz = str.size(withAttributes: attrs)
    str.draw(at:.init(x:(size-sz.width)/2,y:(size-sz.height)/2), withAttributes: attrs)
    img.unlockFocus()
    return img
}

// MARK: – Main
let args = CommandLine.arguments.dropFirst()
guard !args.isEmpty else {
    print("usage: swift icongrab.swift <file> [file …]"); exit(1)
}

for path in args {
    let url = URL(fileURLWithPath: path)
    let img = iconForFile(url)
    let dst = url.deletingPathExtension().appendingPathExtension("icon.png")
    guard let tiff = img.tiffRepresentation,
          let rep  = NSBitmapImageRep(data: tiff),
          let png  = rep.representation(using: .png, properties: [:]) else {
        print("✗ \(path)  →  PNG 生成に失敗"); continue
    }
    try png.write(to: dst)
    print("✓ \(path)  →  \(dst.lastPathComponent)")
}