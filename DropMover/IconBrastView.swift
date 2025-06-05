//
//  IconBlastView.swift (バグ対策付き) – 初回ゴースト/2枚現象回避
//

import AppKit  // macOSのネイティブUIコンポーネントを使用するためのフレームワークをインポート
import QuartzCore
import SwiftUI  // SwiftUIフレームワークをインポート（宣言的UIを構築するため）

struct DualAnimatableLogger: AnimatableModifier {
    var t: CGFloat
    var pos: CGPoint

    var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>> {
        get {
            AnimatablePair(t, AnimatablePair(pos.x, pos.y))
        }
        set {
            t = newValue.first
            pos = CGPoint(x: newValue.second.first, y: newValue.second.second)
            print("DualAnimatableLogger: t = \(t), pos = \(pos)")
        }
    }

    func body(content: Content) -> some View {
        content
    }
}

extension View {
    func logDualAnimatableData(t: CGFloat, pos: CGPoint) -> some View {
        self.modifier(DualAnimatableLogger(t: t, pos: pos))
    }
}

public struct IconBlastModel: Equatable, Identifiable {  // モデル構造体の定義。等価性と識別性を提供
    public let id = UUID()  // ユニークな識別子を生成（どんな場合もユニーク）
    let icons: [NSImage]  // NSImageの配列。使用するアイコンの画像を保持
    let dropPoint: CGPoint  // アイコンのドロップ（落下）位置を保持
    let isize: CGFloat  // アイコンのサイズ

    public static func == (lhs: IconBlastModel, rhs: IconBlastModel) -> Bool {  // 等価比較のための関数
        lhs.id == rhs.id  // 両方のモデルのIDが一致すれば同じと判定
    }
}

struct IconBlastView: View {  // SwiftUIのViewを定義する構造体
    @Binding var model: IconBlastModel?  // 外部からバインディングされるモデル。変化に合わせてUIが更新
    @State private var currentItems: [BlastIcon] = []  // 画面に表示する個々のアニメーションアイコンを保持する状態変数
    @State private var needsInitialCleanup: Bool = true  // 初回のみ行うクリーンアップが必要かどうかのフラグ

    private let win = CGSize(width: 360, height: 240)  // 表示領域のサイズを定義
    private var ctr: CGPoint {
        CGPoint(x: win.width / 2, y: win.height / 2 + 16)  // 左下が(0, 0)、メニューバー???
    }  // 表示領域の中心点を計算
    private static let delayMultiplier: Double = 1.0
    private let schedule: [(Double, Int)] = [  // アニメーションを開始する遅延時間と表示するアイコン数の組み合わせ
        (0.00 * Self.delayMultiplier, 1),  // 0秒後に1つのアイコンを表示
        (0.05 * Self.delayMultiplier, 2),  // 0.05秒後に2つのアイコンを表示
        (0.10 * Self.delayMultiplier, 4),  // 0.10秒後に4つのアイコンを表示
        (0.15 * Self.delayMultiplier, 8),  // 0.15秒後に8つのアイコンを表示
    ]

    var body: some View {  // Viewの本体。画面に表示される内容を定義
        ZStack {  // 複数のViewを重ね合わせるためのZ軸上のコンテナ
            ForEach(currentItems, id: \.id) { item in  // currentItems配列内の各アイテムに対してViewを生成
                SingleIconView(
                    item: item,
                    baseSize: model?.isize ?? 32,
                    ctr: ctr
                ) {  // 単一アイコンのアニメーションViewを生成。finishedクロージャ付き
                    // 最後のアイコンでのみクリーンアップ処理を実行
                    if item.id == currentItems.last?.id {  // 現在のアイコンが最後のアイコンなら
                        DispatchQueue.main.async { model = nil }  // メインスレッドでモデルをnilにしてクリーンアップ
                    }
                }
            }
        }
        .allowsHitTesting(false)  // このViewはタッチやクリックイベントを受け付けないようにする
        .onAppear {  // Viewが初めて表示されたときの処理
            // 初回のみ描画エンジンの「描き残し」対策としてアイテムをクリアする
            if needsInitialCleanup {  // クリーンアップが必要な場合
                currentItems.removeAll()  // 表示中のアイコンリストを全て削除
                // 少し遅延させて初回のみクリーンアップ後の状態にする
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {  // 0.02秒後に実行
                    needsInitialCleanup = false  // 初回クリーンアップ処理済みに更新
                }
            }
        }
        .onChange(of: model) { newModel in  // modelの変更を監視して処理を実行
            // modelがセットされた直後に少し待ってからアニメーションを開始するための処理
            guard let m = newModel else {  // modelがnilの場合は
                currentItems.removeAll()  // 表示中のアイコンリストを削除し
                return  // 処理を終了
            }
            // 遅延させてからアニメーション用のアイテムを生成して設定
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {  // 0.01秒後に実行
                currentItems = makeItems(from: m)  // モデルからBlastIconのリストを生成して設定
            }
        }
    }

    // --- makeItemsとその他の実装は以前のまま ---
    private func makeItems(from m: IconBlastModel) -> [BlastIcon] {  // IconBlastModelをもとにBlastIcon配列を生成する関数
        let dropRad = atan2(
            Double(m.dropPoint.y - ctr.y) + 0.0,  // 落下点と中心の差から角度を計算（ラジアン）
            Double(m.dropPoint.x - ctr.x) + 0.5  // 中心を避けるために0.5ずらす。
        )  // 左上が(0,0) 角度は右が0、右から下を回る右回転
        print(
            "\(m.dropPoint) \(ctr) \(String(format: "%.1f", dropRad * 180 / .pi)) deg"
        )
        var arr: [BlastIcon] = []  // 結果として返すBlastIconを格納する配列
        var idx = 0  // アイコン画像のインデックスを初期化
        for (delay, cnt) in schedule {  // scheduleの各要素（遅延時間とアイコン個数の組）について処理
            for rel in angleTable[cnt] ?? [] where idx < m.icons.count {  // 対応する角度テーブルが存在する場合に角度を1つずつ取得
                let absRad = dropRad + rel * .pi / 180  // ドロップ角度に相対角度をラジアン変換して加算し絶対角度を計算
                arr.append(
                    BlastIcon(
                        id: UUID(),  // アイコンの識別子として現在のインデックスを設定
                        delay: delay,  // scheduleから取得した遅延時間を設定
                        img: {  // アイコンの画像を設定するクロージャを実行
                            let i = m.icons[idx]  // モデルから該当する画像を取得
                            i.isTemplate = false  // 画像をテンプレートモードで描画しないように設定
                            return i  // 取得した画像を返す
                        }(),
                        start: edgePoint(rad: absRad, isize: m.isize),  // 指定された角度から画面エッジ上の開始位置を計算して設定
                        drop: m.dropPoint  // 落下（終了）位置としてモデルのdropPointを設定
                    )
                )
                idx += 1  // 次のアイコンのためにインデックスをインクリメント
            }
        }
        return arr  // 生成したBlastIcon配列を返す
    }

    private func edgePoint(rad: Double, isize: CGFloat) -> CGPoint {  // 指定した角度から画面のエッジ上の点を計算する関数
        // rad は右が0度、上が90度、左が180度、下が270度のラジアン値
        // ctr は右が+x、上が+yの座標系で、winは画面のサイズ
        let vx = cos(rad)  // 指定角度のx方向の成分を計算
        let vy = sin(rad)  // 指定角度のy方向の成分を計算

        // x方向とy方向のエッジまでの距離を計算
        let distL: CGFloat = ctr.x + isize / 2
        let distR: CGFloat = win.width - ctr.x + isize / 2
        let distT: CGFloat = win.height - ctr.y + isize / 2
        let distB: CGFloat = ctr.y + isize / 2
        let distX: CGFloat = vx >= 0 ? distR : distL
        let distY: CGFloat = vy >= 0 ? distB : distT

        // 角度を加味したx方向とy方向のエッジまでの距離
        let tX: CGFloat = distX / abs(CGFloat(vx))  // x方向の交点までの距離を計算
        let tY: CGFloat = distY / abs(CGFloat(vy))  // y方向の交点までの距離を計算
        let t = min(tX, tY)  // x方向とy方向のうち、画面内に入る早い方の距離を使用
        let start = CGPoint(
            x: ctr.x + t * CGFloat(vx),  // 中心座標からx方向に伸ばしてエッジ上のx座標を計算
            y: ctr.y + t * CGFloat(vy)  // 中心座標からy方向に伸ばしてエッジ上のy座標を計算
        )
        // start位置をprintする。
        print(
            "edgePoint: \(String(format: "%.1f", rad * 180 / .pi)) deg, start=\(start)"
        )

        return start
    }

    struct BlastIcon: Identifiable {  // 個々のアイコンアニメーション用のデータ構造体（Identifiableプロトコルに準拠）
        let id: UUID  // 各アイコンを識別するためのID
        let delay: Double  // アニメーション開始前の遅延時間
        let img: NSImage  // アイコンに使用する画像
        let start: CGPoint  // アニメーション開始時の位置
        let drop: CGPoint  // アニメーション終了時の（落下）位置
    }
}

private let angleTable: [Int: [Double]] = [  // アイコン数に応じた配置角度（相対角度）のテーブル
    1: [0],  // 1個の場合は真上（0度）を使用
    2: [120, 240],  // 2個の場合は120度と240度を使用
    4: [30, 90, 180, 300],  // 4個の場合の配置角度リスト
    8: [60, 150, 210, 270, 330, 15, 105, 255],  // 8個の場合の配置角度リスト
]

// MARK: - Single icon view
private struct SingleIconView: View {
    let item: IconBlastView.BlastIcon
    let baseSize: CGFloat
    let ctr: CGPoint
    let finished: () -> Void

    private let animTime = 0.5  // アニメーションの実行時間

    var body: some View {
        let v: CGVector = CGVector(dx: item.start.x - ctr.x, dy: item.start.y - ctr.y)
        let len = sqrt(v.dx * v.dx + v.dy * v.dy)
        let dir = CGVector(dx: v.dx / len, dy: v.dy / len)
        let right = CGVector(dx: -dir.dy, dy: dir.dx)
        let mid = CGPoint(
            x: (item.start.x + 2 * ctr.x) / 3,
            y: (item.start.y + 2 * ctr.y) / 3
        )
        // 中間の制御点（over）の計算
        let over = CGPoint(
            x: mid.x + right.dx * len * 0.8,
            y: mid.y + right.dy * len * 0.8
        )
        // 二次ベジェ曲線を作成
        let path = CGMutablePath()
        path.move(to: item.start)
        path.addQuadCurve(to: ctr, control: over)

        return PathAnimationImage(
            image: item.img,
            baseSize: baseSize,
            path: path,
            duration: animTime,
            delay: item.delay,
            start: item.start,  // ここで初期位置を渡す
            finished: finished
        )
    }
}

struct PathAnimationImage: NSViewRepresentable {
    let image: NSImage
    let baseSize: CGFloat
    let path: CGPath
    let duration: CFTimeInterval
    let delay: CFTimeInterval
    let start: CGPoint  // 新規追加：初期位置
    let finished: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(finished: finished)
    }

    func makeNSView(context: Context) -> NSView {
        let container = NSView(frame: .zero)
        container.wantsLayer = true

        // イメージレイヤーの作成
        let imageLayer = CALayer()
        imageLayer.contents = image
        imageLayer.contentsGravity = .resizeAspectFill
        imageLayer.bounds = CGRect(x: 0, y: 0, width: baseSize, height: baseSize)
        imageLayer.position = start  // 始点を明示的に設定
        container.layer?.addSublayer(imageLayer)
        
        // パスに沿った位置アニメーションの作成
        let positionAnimation = CAKeyframeAnimation(keyPath: "position")
        positionAnimation.path = path

        // 進捗に合わせた縮小アニメーション（scale 1 -> 0.1）
        let scaleAnimation = CABasicAnimation(keyPath: "transform.scale")
        scaleAnimation.fromValue = 1.0
        scaleAnimation.toValue = 0.05

        // 進捗に合わせた透過アニメーション（opacity 1 -> 0.1）
        let opacityAnimation = CABasicAnimation(keyPath: "opacity")
        opacityAnimation.fromValue = 1.0
        opacityAnimation.toValue = 0.2

        // これらのアニメーションをグループ化
        let group = CAAnimationGroup()
        group.animations = [positionAnimation, scaleAnimation, opacityAnimation]
        group.duration = duration
        group.beginTime = CACurrentMediaTime() + delay
        group.timingFunction = CAMediaTimingFunction(name: .easeIn)
        group.fillMode = .forwards
        group.isRemovedOnCompletion = false
        group.delegate = context.coordinator
        
        imageLayer.add(group, forKey: "animationGroup")
        // 修正：Coordinator に imageLayer を伝える
        context.coordinator.imageLayer = imageLayer

        return container
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        // 必要に応じた更新処理
    }

    class Coordinator: NSObject, CAAnimationDelegate {
        let finished: () -> Void
        // imageLayerを弱参照で保持
        weak var imageLayer: CALayer?
        
        init(finished: @escaping () -> Void) {
            self.finished = finished
        }
        
        func animationDidStop(_ anim: CAAnimation, finished flag: Bool) {
            if flag {
                DispatchQueue.main.async {
                    // アニメーション終了時に imageLayer を削除
                    self.imageLayer?.removeFromSuperlayer()
                    // その後 finished クロージャで画面側の削除処理を実行
                    self.finished()
                }
            }
        }
    }
}
