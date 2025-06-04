//
//  IconBlastView.swift - SMART, NO DUPLICATES, DEBUG READY
//

import AppKit
import SwiftUI

// MARK: - Model
public struct IconBlastModel: Equatable, Identifiable {
    public let id = UUID()
    let icons: [NSImage]
    let dropPoint: CGPoint

    // すべてのプロパティで厳密比較
    public static func == (lhs: IconBlastModel, rhs: IconBlastModel) -> Bool {
        lhs.id == rhs.id  // ← これで絶対一意
    }
}

// MARK: - Angle table
private let angleTable: [Int: [Double]] = [
    1: [0],
    2: [120, 240],
    4: [300, 30, 120, 210],
    8: [90, 105, 120, 135, 150, 165, 180, 195],
]

// MARK: - Main View
struct IconBlastView: View {
    @Binding var model: IconBlastModel?

    // 現在表示しているアイコン配列
    @State private var currentItems: [BlastIcon] = []
    @State private var animationSerial = 0  // アニメーション世代追跡

    private let win = CGSize(width: 360, height: 240)
    private var ctr: CGPoint { .init(x: win.width / 2, y: win.height / 2) }
    private let schedule: [(Double, Int)] = [
        (0.00, 1), (0.05, 2), (0.10, 4), (0.15, 8),
    ]

    var body: some View {
        let _ = Self._printChanges()
        ZStack {
            ForEach(currentItems, id: \.identity) { item in
                SingleIconView(item: item) { finishedID in
                    debugPrint(
                        "🟦 [\(animationSerial)] SingleIconView.finished: \(finishedID)"
                    )
                    // 全アイコン終わったらmodel=nil
                    if finishedID == currentItems.last?.identity {
                        debugPrint(
                            "🟧 [\(animationSerial)] All icons finished, cleaning up!"
                        )
                        // model = nil 直後にcurrentItemsも即座に空になる
                        DispatchQueue.main.async {
                            model = nil
                        }
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            debugPrint(
                "⭐️ IconBlastView.onAppear (init state: model is nil? \(model == nil))"
            )
            // 完全な初期化時は何もしない
        }
        .onDisappear {
            debugPrint("🚪 IconBlastView.onDisappear()")
        }
        .onChange(of: model) { [old = model] newModel in
            debugPrint(
                "🔄 [\(animationSerial)] onChange(model): old = \(String(describing: old?.id)), new = \(String(describing: newModel?.id))"
            )
            if let m = newModel {
                animationSerial += 1
                let items = makeItems(from: m, serial: animationSerial)
                currentItems = items
                dumpSummary(m, items)
            } else {
                debugPrint("🧹 onChange(model): model=nil, clearing items.")
                currentItems = []
            }
        }
    }

    // MARK: - アイテム生成
    private func makeItems(from m: IconBlastModel, serial: Int) -> [BlastIcon] {
        let dropRad = atan2(
            Double(m.dropPoint.y - ctr.y),
            Double(m.dropPoint.x - ctr.x)
        )
        var arr: [BlastIcon] = []
        var idx = 0
        for (delay, cnt) in schedule {
            for rel in angleTable[cnt] ?? [] where idx < m.icons.count {
                let absRad = dropRad + rel * .pi / 180
                let icon = m.icons[idx]
                icon.isTemplate = false
                arr.append(
                    BlastIcon(
                        serial: serial,
                        id: idx,
                        img: icon,
                        delay: delay,
                        start: edgePoint(rad: absRad),
                        drop: m.dropPoint
                    )
                )
                idx += 1
            }
        }
        for i in arr {
            debugPrint(
                "  · [SER:\(serial)] id=\(i.id) delay=\(i.delay) start=(\(Int(i.start.x)),\(Int(i.start.y)))"
            )
        }
        return arr
    }

    private func edgePoint(rad: Double) -> CGPoint {
        let vx = cos(rad)
        let vy = sin(rad)
        let tX =
            vx >= 0
            ? (win.width - ctr.x) / CGFloat(vx) : (0 - ctr.x) / CGFloat(vx)
        let tY =
            vy >= 0
            ? (win.height - ctr.y) / CGFloat(vy) : (0 - ctr.y) / CGFloat(vy)
        let t = CGFloat(min(tX, tY))
        return CGPoint(
            x: ctr.x + t * CGFloat(vx),
            y: ctr.y + t * CGFloat(vy)
        )
    }

    private func dumpSummary(_ m: IconBlastModel, _ items: [BlastIcon]) {
        let deg =
            atan2(Double(m.dropPoint.y - ctr.y), Double(m.dropPoint.x - ctr.x))
            * 180 / Double.pi
        debugPrint("🔹 IconBlast summary ────────")
        debugPrint(
            "window : \(Int(win.width))×\(Int(win.height)), center=(\(Int(ctr.x)),\(Int(ctr.y)))"
        )
        debugPrint(
            "drop   : (\(Int(m.dropPoint.x)),\(Int(m.dropPoint.y)))  dir=\(String(format:"%.1f",deg))°"
        )
        debugPrint("icons  : \(m.icons.count)")
        for ic in items {
            let absDeg = ic.start.angleDeg(from: ctr)
            debugPrint(
                String(
                    format:
                        "  · id=%02d delay=%.2f  abs=%.1f° start=(%.0f,%.0f)",
                    ic.id,
                    ic.delay,
                    absDeg,
                    ic.start.x,
                    ic.start.y
                )
            )
        }
    }

    // MARK: - BlastIcon
    struct BlastIcon: Identifiable {
        let serial: Int  // アニメーション世代(Playボタンの押下回数)
        let id: Int  // 配列内の連番
        let img: NSImage
        let delay: Double
        let start: CGPoint
        let drop: CGPoint

        var identity: String { "\(serial)-\(id)" }
    }
}

// MARK: - Single icon view
private struct SingleIconView: View {
    let item: IconBlastView.BlastIcon
    let finished: (String) -> Void
    @State private var t = 0.0  // 0 → 1

    private let animTime = 2.0
    private let baseSize: CGFloat = 128

    var body: some View {
        let ctr = CGPoint(x: 180, y: 120)
        // direction & right-hand vector
        let v = CGVector(dx: item.drop.x - ctr.x, dy: item.drop.y - ctr.y)
        let len = sqrt(v.dx * v.dx + v.dy * v.dy)
        let dir = CGVector(dx: v.dx / len, dy: v.dy / len)
        let right = CGVector(dx: dir.dy, dy: -dir.dx)

        let mid = CGPoint(
            x: (item.start.x + ctr.x) / 2,
            y: (item.start.y + ctr.y) / 2
        )
        let over = CGPoint(
            x: mid.x + right.dx * len * 0.5,
            y: mid.y + right.dy * len * 0.5
        )

        func bezier(_ s: CGFloat) -> CGPoint {
            let u = 1 - s
            return CGPoint(
                x: u * u * item.start.x + 2 * u * s * over.x + s * s * ctr.x,
                y: u * u * item.start.y + 2 * u * s * over.y + s * s * ctr.y
            )
        }
        let pos = bezier(CGFloat(t))

        return Image(nsImage: item.img)
            .renderingMode(.original)
            .resizable()
            .frame(width: baseSize, height: baseSize)
            .position(pos)
            .scaleEffect(1 - t)
            .opacity(1 - t)
            .onAppear {
                debugPrint("▶️ SingleIconView.onAppear: \(item.identity)")
                withAnimation(.easeIn(duration: animTime).delay(item.delay)) {
                    t = 1
                }
                // アニメ完了で通知
                DispatchQueue.main.asyncAfter(
                    deadline: .now() + item.delay + animTime
                ) {
                    finished(item.identity)
                }
            }
    }
}

// MARK: - CGPoint helper
extension CGPoint {
    fileprivate func angleDeg(from origin: CGPoint) -> Double {
        let dx = Double(x - origin.x)
        let dy = Double(y - origin.y)
        return atan2(dy, dx) * 180 / Double.pi
    }
}
