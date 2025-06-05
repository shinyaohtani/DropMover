//
//  IconBlastView.swift (バグ対策付き) – 初回ゴースト/2枚現象回避
//

import AppKit  // macOSのネイティブUIコンポーネントを使用するためのフレームワークをインポート
import SwiftUI  // SwiftUIフレームワークをインポート（宣言的UIを構築するため）

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
        CGPoint(x: win.width / 2, y: win.height / 2 - 16)  // 左上が(0, 0)、メニューバー???
    }  // 表示領域の中心点を計算
    private let schedule: [(Double, Int)] = [  // アニメーションを開始する遅延時間と表示するアイコン数の組み合わせ
        (0.00 * 11, 1),  // 0秒後に1つのアイコンを表示
        (0.05 * 11, 2),  // 0.05秒後に2つのアイコンを表示
        (0.10 * 11, 4),  // 0.10秒後に4つのアイコンを表示
        (0.15 * 11, 8),  // 0.15秒後に8つのアイコンを表示
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
            Double(m.dropPoint.y - ctr.y) + 0.2,  // 落下点と中心の差から角度を計算（ラジアン）
            Double(m.dropPoint.x - ctr.x) + 0.5  // 中心を避けるために0.5ずらす。
        )  // 左上が(0,0) 角度は右が0、右から下を回る右回転
        print("{\(m.dropPoint.x),\(m.dropPoint.y)} {\(ctr.x),\(ctr.y)} \(dropRad * 180 / .pi) deg")
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
        // rad は右が0度、下が90度、左が180度、右が270度のラジアン値
        // ctr は右が+x、下が+yの座標系で、winは画面のサイズ
        let vx = cos(rad)  // 指定角度のx方向の成分を計算
        let vy = sin(rad)  // 指定角度のy方向の成分を計算

        // x方向とy方向のエッジまでの距離を計算
        let distL: CGFloat = ctr.x + isize / 2
        let distR: CGFloat = win.width - ctr.x + isize / 2
        let distT: CGFloat = ctr.y + isize / 2
        let distB: CGFloat = win.height - ctr.y + isize / 2
        let distX: CGFloat = vx >= 0 ? distR : distL
        let distY: CGFloat = vy >= 0 ? distB : distT

        // 角度を加味したx方向とy方向のエッジまでの距離
        let tX: CGFloat = distX / abs(CGFloat(vx))  // x方向の交点までの距離を計算
        let tY: CGFloat = distY / abs(CGFloat(vy))  // y方向の交点までの距離を計算
        let t = min(tX, tY)  // x方向とy方向のうち、画面内に入る早い方の距離を使用
        return CGPoint(
            x: ctr.x + t * CGFloat(vx),  // 中心座標からx方向に伸ばしてエッジ上のx座標を計算
            y: ctr.y + t * CGFloat(vy)  // 中心座標からy方向に伸ばしてエッジ上のy座標を計算
        )
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
private struct SingleIconView: View {  // 単一のアイコンを表示するViewの定義
    let item: IconBlastView.BlastIcon  // 表示するアイコンのデータを受け取る
    let baseSize: CGFloat  // アイコン画像の基本サイズを指定
    let ctr: CGPoint
    let finished: () -> Void  // アニメーション完了時に実行されるクロージャ

    @State private var t = 0.0  // アニメーションの進捗（0.0～1.0）を管理する状態変数

    private let animTime = 2.0  // アニメーションの実行時間を指定（秒単位）

    var body: some View {  // 単一アイコンの表示内容を定義する
        let v = CGVector(dx: item.drop.x - ctr.x, dy: item.drop.y - ctr.y)  // 中心点から落下位置へのベクトルを計算
        let len = sqrt(v.dx * v.dx + v.dy * v.dy)  // そのベクトルの長さ（距離）を計算
        let dir = CGVector(dx: v.dx / len, dy: v.dy / len)  // 距離で割って正規化し、方向ベクトルを求める
        let right = CGVector(dx: dir.dy, dy: -dir.dx)  // 落下方向に対して直交する右方向のベクトルを計算
        let mid = CGPoint(
            x: (item.start.x + ctr.x) / 2,  // 開始位置と中心点のx座標の中間地点を計算
            y: (item.start.y + ctr.y) / 2  // 開始位置と中心点のy座標の中間地点を計算
        )
        let over = CGPoint(
            x: mid.x + right.dx * len * 0.5,  // 中間地点から右方向へずらした座標を計算
            y: mid.y + right.dy * len * 0.5  // 中間地点から右方向へずらした座標を計算
        )
        func bezier(_ s: CGFloat) -> CGPoint {  // 進捗sに基づいて二次ベジェ曲線上の点を計算する関数
            let u = 1 - s  // 補数を計算（開始地点の重み）
            return CGPoint(
                x: u * u * item.start.x + 2 * u * s * over.x + s * s * ctr.x,  // x座標の二次ベジェ補間
                y: u * u * item.start.y + 2 * u * s * over.y + s * s * ctr.y  // y座標の二次ベジェ補間
            )
        }
        let pos = bezier(CGFloat(t))  // 現在の進捗tから現在のアイコン位置を計算
        return Image(nsImage: item.img)  // NSImageからSwiftUIのImageを生成
            .renderingMode(.original)  // 画像を元のカラーで描画するよう指定
            .resizable()  // 画像のサイズ変更を許可
            .frame(width: baseSize, height: baseSize)  // 表示サイズをbaseSizeに設定
            .position(pos)  // 計算したposの位置に画像を配置
            .scaleEffect(1 - t)  // 進捗tに応じてアイコンを縮小させる（1から0まで縮小）
            .opacity(1 - t)  // 進捗tに応じて透過させる（1から0までフェードアウト）
            .onAppear {  // アイコンのViewが表示されたときの処理
                withAnimation(.easeIn(duration: animTime).delay(item.delay)) {  // easeInのアニメーションを指定し、遅延後に実行
                    t = 1  // アニメーションが完了するとtが1になる（最終位置・サイズになる）
                }
                DispatchQueue.main.asyncAfter(
                    deadline: .now() + item.delay + animTime,  // 遅延時間とアニメーション時間を合算した後に
                    execute: finished  // アニメーション完了時のクロージャを実行して後続処理を行う
                )
            }
    }
}
