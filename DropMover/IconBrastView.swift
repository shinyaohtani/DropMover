import SwiftUI
import AppKit

// MARK: - モデル ---------------------------------------------------------------
struct IconBlastModel {
    let icons: [NSImage]   // 先頭 15 件
    let dropPoint: CGPoint // ドロップ座標（左下原点）
}

// MARK: - 角度テーブル（0°=ドロップ方向、反時計回り）
private let angleTable: [Int: [Double]] = [
    1: [0],
    2: [120, 240],
    4: [300, 30, 120, 210],
    8: [90, 105, 120, 135, 150, 165, 180, 195],
]

// MARK: - メイン View ----------------------------------------------------------
struct IconBlastView: View {
    @Binding var model: IconBlastModel?
    private let win = CGSize(width: 360, height: 240)
    private var center: CGPoint { .init(x: win.width / 2, y: win.height / 2) }

    /// 発射スケジュール (delay 秒, 枚数)
    private let schedule: [(Double, Int)] = [(0,1),(0.05,2),(0.10,4),(0.15,8)]

    var body: some View {
        ZStack {
            ForEach(makeItems(), id: \.id) { item in
                SingleIconView(item: item) {
                    if item.id == makeItems().last?.id { model = nil }
                }
            }
        }
        .allowsHitTesting(false)
    }

    //――― BlastIcon を生成 -----------------------------------------------------
    private func makeItems() -> [BlastIcon] {
        guard let m = model else { return [] }

        /// ドロップ方向を基準 0°
        let dropDir = atan2(
            Double(m.dropPoint.y - center.y),
            Double(m.dropPoint.x - center.x)
        )

        var out: [BlastIcon] = []
        var idx = 0
        for (delay, cnt) in schedule {
            let rels = angleTable[cnt] ?? []
            for rel in rels where idx < m.icons.count {
                let absRad = dropDir + rel * .pi / 180
                let start = edgePoint(angle: absRad)
                out.append(.init(id: idx,
                                 delay: delay,
                                 image: prepared(m.icons[idx]),
                                 start: start,
                                 drop: m.dropPoint,
                                 dirRad: absRad))
                idx += 1
            }
        }
        return out
    }

    /// ウィンドウ矩形と光線 angle が交わる点を返す
    private func edgePoint(angle rad: Double) -> CGPoint {
        let vx = cos(rad), vy = sin(rad)
        let tx = (vx >= 0 ? win.width - center.x : -center.x) / vx
        let ty = (vy >= 0 ? win.height - center.y : -center.y) / vy
        let t  = CGFloat(min(tx, ty))
        return .init(x: center.x + t * CGFloat(vx),
                     y: center.y + t * CGFloat(vy))
    }

    /// NSImage がテンプレートならカラー表示にする
    private func prepared(_ img: NSImage) -> NSImage {
        img.isTemplate = false; return img
    }

    // 描画用データ
    struct BlastIcon: Identifiable {
        let id: Int
        let delay: Double
        let image: NSImage
        let start: CGPoint
        let drop: CGPoint
        let dirRad: Double
    }
}

// MARK: - 単一アイコン ---------------------------------------------------------
private struct SingleIconView: View {
    let item: IconBlastView.BlastIcon
    let finished: () -> Void
    @State private var t = 0.0           // 0 → 1

    private let animTime: Double = 2.0
    private let baseSize: CGFloat = 128  // 128px → 0

    var body: some View {
        let center = CGPoint(x: 180, y: 120)

        /// ノーマライズ方向ベクトル
        let dx = item.drop.x - center.x, dy = item.drop.y - center.y
        let len = sqrt(dx*dx + dy*dy)
        let dir = CGVector(dx: dx/len, dy: dy/len)

        /// 右手法線
        let right = CGVector(dx: dir.dy, dy: -dir.dx)

        /// 張り出し点： midpoint + 0.5R * right
        let mid = CGPoint(x: (item.start.x + center.x)/2,
                          y: (item.start.y + center.y)/2)
        let overshoot = CGPoint(
            x: mid.x + right.dx * len * 0.5,
            y: mid.y + right.dy * len * 0.5
        )

        /// 2 次ベジェ補間
        func bezier(_ t: CGFloat) -> CGPoint {
            let u = 1 - t
            let p0 = item.start, p1 = overshoot, p2 = center
            let x = u*u*p0.x + 2*u*t*p1.x + t*t*p2.x
            let y = u*u*p0.y + 2*u*t*p1.y + t*t*p2.y
            return CGPoint(x: x, y: y)
        }

        let pos = bezier(CGFloat(t))

        return Image(nsImage: item.image)
            .renderingMode(.original)
            .resizable()
            .frame(width: baseSize, height: baseSize)
            .position(pos)
            .scaleEffect(1 - t)
            .opacity(1 - t)
            .onAppear {
                withAnimation(.easeIn(duration: animTime)
                                .delay(item.delay)) { t = 1 }
                DispatchQueue.main.asyncAfter(
                    deadline: .now() + item.delay + animTime,
                    execute: finished)
            }
    }
}
