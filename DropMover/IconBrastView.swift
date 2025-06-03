//
//  IconBlastView.swift  – debug logging & correct math
//

import SwiftUI
import AppKit

// MARK: - Model passed from SheetView
public struct IconBlastModel {
    let icons: [NSImage]     // first ≤15 icons
    let dropPoint: CGPoint   // drop position, left-bottom origin (0,0)
}

// MARK: - Angle table (deg, CCW, 0° = drop direction)
private let angleTable: [Int:[Double]] = [
    1 : [0],
    2 : [120, 240],
    4 : [300,  30, 120, 210],
    8 : [ 90, 105, 120, 135, 150, 165, 180, 195]
]

// MARK: - Main view
struct IconBlastView: View {
    @Binding var model: IconBlastModel?          // nil → hidden

    private let win = CGSize(width: 360, height: 240)
    private var ctr: CGPoint { .init(x: win.width/2, y: win.height/2) }
    private let schedule: [(Double,Int)] = [(0,1),(0.05,2),(0.10,4),(0.15,8)]

    // ----------------------------------------------------------------------------
    var body: some View {
        ZStack {
            ForEach(makeItems(), id: \.id) { ic in
                SingleIconView(item: ic) {
                    if ic.id == makeItems().last?.id { model = nil }
                }
            }
        }
        .allowsHitTesting(false)
        // Debug summary once when new model arrives
        .onChange(of: model?.dropPoint) { _ in dumpSummary() }
    }

    // ----------------------------------------------------------------------------
    /// convert model → BlastIcon list following schedule
    private func makeItems() -> [BlastIcon] {
        guard let m = model else { return [] }

        // drop direction (rad)
        let dropRad = atan2(Double(m.dropPoint.y - ctr.y),
                            Double(m.dropPoint.x - ctr.x))

        var arr: [BlastIcon] = []; var idx = 0
        for (delay, cnt) in schedule {
            for rel in angleTable[cnt] ?? [] where idx < m.icons.count {
                let absRad = dropRad + rel * .pi / 180
                arr.append(
                    BlastIcon(
                        id: idx,
                        delay: delay,
                        img: { let i=m.icons[idx]; i.isTemplate=false; return i }(),
                        start: edgePoint(rad: absRad),
                        drop: m.dropPoint
                    )
                )
                idx += 1
            }
        }
        arr.forEach { dumpIcon($0, dropRad: dropRad) }   // per-icon log
        return arr
    }

    /// intersect ray(rad) with window rectangle and return edge point
    private func edgePoint(rad: Double) -> CGPoint {
        let vx = cos(rad), vy = sin(rad)
        // t when hitting each vertical / horizontal edge
        let tX = vx >= 0 ? (win.width  - ctr.x) / vx
                         : (0          - ctr.x) / vx
        let tY = vy >= 0 ? (win.height - ctr.y) / vy
                         : (0          - ctr.y) / vy
        let t  = CGFloat(min(tX, tY))
        return CGPoint(x: ctr.x + t * CGFloat(vx),
                       y: ctr.y + t * CGFloat(vy))
    }

    // MARK: - Debug print helpers ----------------------------------------------
    private func dumpSummary() {
        guard let m = model else { return }
        print("🔹 IconBlast summary ────────")
        let deg = atan2(Double(m.dropPoint.y-ctr.y),
                        Double(m.dropPoint.x-ctr.x))*180/Double.pi
        print("window : \(Int(win.width))×\(Int(win.height)), center=(\(Int(ctr.x)),\(Int(ctr.y)))")
        print("drop   : (\(Int(m.dropPoint.x)),\(Int(m.dropPoint.y)))  dir=\(String(format:"%.1f",deg))°")
        print("icons  : \(m.icons.count)")
    }
    private func dumpIcon(_ ic: BlastIcon, dropRad: Double) {
        let absDeg = ic.start.angleDeg(from: ctr)
        print(String(format:"  · id=%02d delay=%.2f  abs=%.1f° start=(%.0f,%.0f)",
                     ic.id, ic.delay, absDeg, ic.start.x, ic.start.y))
    }

    // MARK: - Internal data ----------------------------------------------------
    struct BlastIcon: Identifiable {
        let id: Int
        let delay: Double
        let img: NSImage
        let start: CGPoint
        let drop: CGPoint
    }
}

// MARK: - Single icon view
private struct SingleIconView: View {
    let item: IconBlastView.BlastIcon
    let finished: () -> Void
    @State private var t = 0.0                          // 0 → 1

    private let animTime = 2.0                          // 2 s
    private let baseSize: CGFloat = 128

    var body: some View {
        let ctr = CGPoint(x: 180, y: 120)

        // direction & right-hand vector
        let v  = CGVector(dx: item.drop.x - ctr.x, dy: item.drop.y - ctr.y)
        let len = sqrt(v.dx*v.dx + v.dy*v.dy)
        let dir = CGVector(dx: v.dx/len, dy: v.dy/len)
        let right = CGVector(dx: dir.dy, dy: -dir.dx)

        // overshoot point = midpoint + 0.5·len·right
        let mid = CGPoint(x: (item.start.x + ctr.x)/2,
                          y: (item.start.y + ctr.y)/2)
        let over = CGPoint(x: mid.x + right.dx * len * 0.5,
                           y: mid.y + right.dy * len * 0.5)

        // Quadratic Bézier interpolation
        func bezier(_ s: CGFloat) -> CGPoint {
            let u = 1 - s
            return CGPoint(
                x: u*u*item.start.x + 2*u*s*over.x + s*s*ctr.x,
                y: u*u*item.start.y + 2*u*s*over.y + s*s*ctr.y
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
                DispatchQueue.main.asyncAfter(deadline: .now() + item.delay + animTime,
                                              execute: finished)
            }
    }
}

// MARK: - CGPoint helper
private extension CGPoint {
    /// angle in degree (0 = +X axis) from `origin`
    func angleDeg(from origin: CGPoint) -> Double {
        let dx = Double(x - origin.x), dy = Double(y - origin.y)
        return atan2(dy, dx) * 180 / Double.pi
    }
}
