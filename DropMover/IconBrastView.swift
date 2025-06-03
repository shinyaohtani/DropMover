//
//  IconBrastView.swift
//  DropMover
//
//  Created by 大谷伸弥 on 2025/06/03.
//

import SwiftUI
import AppKit

// MARK: - Public model --------------------------------------------------------
struct IconBlastModel {
    let icons: [NSImage]       // 先頭 15 件
    let dropPoint: CGPoint     // ドロップ位置（ウィンドウ座標系）
}

// MARK: - Main blast view -----------------------------------------------------
struct IconBlastView: View {
    @Binding var model: IconBlastModel?   // nil で非表示

    private let windowSize = CGSize(width: 360, height: 240)
    private let schedule = [ (0.00, 1),
                             (0.05, 2),
                             (0.10, 4),
                             (0.15, 8) ]      // (delay, count)

    var body: some View {
        ZStack {
            ForEach(emittedItems(), id: \.id) { item in
                SingleIconView(item: item) {
                    // 全アイコン完了後にモデルを破棄
                    if item.id == emittedItems().last?.id {
                        DispatchQueue.main.async { model = nil }
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }

    // ------------------------------------------------------------------------
    // helpers
    private func emittedItems() -> [BlastIcon] {
        guard let m = model else { return [] }
        var result: [BlastIcon] = []
        var index = 0
        for (delay, count) in schedule {
            for j in 0..<count where index < m.icons.count {
                let angleDeg = angleTable[count]?[j] ?? 0
                result.append(.init(id: index,
                                    image: m.icons[index],
                                    delay: delay,
                                    startAngle: angleDeg,
                                    dropPoint: m.dropPoint))
                index += 1
            }
        }
        return result
    }

    // 角度テーブル（0°基準・反時計回り）
    private let angleTable: [Int:[Double]] = [
        1  : [0],
        2  : [120, 240],
        4  : [300, 30, 120, 210],
        8  : [90,105,120,135,150,165,180,195]
    ]

    // blast icon description
    struct BlastIcon: Identifiable {
        let id: Int
        let image: NSImage
        let delay: Double
        let startAngle: Double
        let dropPoint: CGPoint
    }
}

// MARK: - Single icon animatable ---------------------------------------------
private struct SingleIconView: View {
    let item: IconBlastView.BlastIcon
    let completion: () -> Void

    @State private var t: Double = 0          // 0 → 1 over 0.2 s

    private let duration = 0.5
    private let κ = Double.pi * 1.8           // 左巻きカーブ係数

    var body: some View {
        let radius: CGFloat = 180             // ウィンドウ外縁 ~ 任意
        let startRad = item.startAngle * Double.pi / 180
        let cx = item.dropPoint.x - 180       // translate to ± coords
        let cy = item.dropPoint.y - 120

        // current polar -> cartesian
        let currentR = radius * (1 - t)
        let currentθ = startRad + κ * pow(t, 2)
        let x = cx + currentR * cos(currentθ)
        let y = cy + currentR * sin(currentθ)

        return Image(nsImage: item.image)
            .resizable()
            .frame(width: 128, height: 128)
            .position(x: x + 180, y: y + 120)             // back to view coords
            .scaleEffect(1 - t)
            .opacity(1 - t)
            .onAppear {
                withAnimation(.easeIn(duration: duration).delay(item.delay)) {
                    t = 1
                }
                // schedule completion after animation
                DispatchQueue.main.asyncAfter(deadline: .now() + item.delay + duration, execute: completion)
            }
    }
}
