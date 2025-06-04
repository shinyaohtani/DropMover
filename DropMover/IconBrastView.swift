//
//  IconBlastView.swift (バグ対策付き) – 初回ゴースト/2枚現象回避
//

import AppKit
import SwiftUI

public struct IconBlastModel: Equatable, Identifiable {
    public let id = UUID()  // どんな場合もユニーク
    let icons: [NSImage]
    let dropPoint: CGPoint

    public static func == (lhs: IconBlastModel, rhs: IconBlastModel) -> Bool {
        lhs.id == rhs.id
    }
}

struct IconBlastView: View {
    @Binding var model: IconBlastModel?
    @State private var currentItems: [BlastIcon] = []
    @State private var needsInitialCleanup: Bool = true

    private let win = CGSize(width: 360, height: 240)
    private var ctr: CGPoint { CGPoint(x: win.width / 2, y: win.height / 2) }
    private let schedule: [(Double, Int)] = [
        (0.00, 1),
        (0.05, 2),
        (0.10, 4),
        (0.15, 8),
    ]

    var body: some View {
        ZStack {
            ForEach(currentItems, id: \.id) { item in
                SingleIconView(item: item) {
                    // 最後のアイコンでのみクリーンアップ
                    if item.id == currentItems.last?.id {
                        DispatchQueue.main.async { model = nil }
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            // 初回だけ、描画エンジンの「描き残し」対策としてアイテムを強制クリア
            if needsInitialCleanup {
                currentItems.removeAll()
                // ほんの少し遅延して初回だけクリア
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                    needsInitialCleanup = false
                }
            }
        }
        .onChange(of: model) { newModel in
            // modelセット直後は一呼吸置いてアニメ開始
            guard let m = newModel else {
                currentItems.removeAll()
                return
            }
            // 再生を少し遅らせてレイヤー初期化を確実に
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                currentItems = makeItems(from: m)
            }
        }
    }

    // --- makeItemsとその他の実装は以前のまま ---
    private func makeItems(from m: IconBlastModel) -> [BlastIcon] {
        let dropRad = atan2(
            Double(m.dropPoint.y - ctr.y),
            Double(m.dropPoint.x - ctr.x)
        )
        var arr: [BlastIcon] = []
        var idx = 0
        for (delay, cnt) in schedule {
            for rel in angleTable[cnt] ?? [] where idx < m.icons.count {
                let absRad = dropRad + rel * .pi / 180
                arr.append(
                    BlastIcon(
                        id: idx,
                        delay: delay,
                        img: {
                            let i = m.icons[idx]
                            i.isTemplate = false
                            return i
                        }(),
                        start: edgePoint(rad: absRad),
                        drop: m.dropPoint
                    )
                )
                idx += 1
            }
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
        let t = min(tX, tY)
        return CGPoint(
            x: ctr.x + t * CGFloat(vx),
            y: ctr.y + t * CGFloat(vy)
        )
    }

    struct BlastIcon: Identifiable {
        let id: Int
        let delay: Double
        let img: NSImage
        let start: CGPoint
        let drop: CGPoint
    }
}

private let angleTable: [Int: [Double]] = [
    1: [0],
    2: [120, 240],
    4: [300, 30, 120, 210],
    8: [90, 105, 120, 135, 150, 165, 180, 195],
]

// MARK: - Single icon view
private struct SingleIconView: View {
    let item: IconBlastView.BlastIcon
    let finished: () -> Void
    @State private var t = 0.0

    private let animTime = 2.0
    private let baseSize: CGFloat = 128

    var body: some View {
        let ctr = CGPoint(x: 180, y: 120)
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
                withAnimation(.easeIn(duration: animTime).delay(item.delay)) {
                    t = 1
                }
                DispatchQueue.main.asyncAfter(
                    deadline: .now() + item.delay + animTime,
                    execute: finished
                )
            }
    }
}
