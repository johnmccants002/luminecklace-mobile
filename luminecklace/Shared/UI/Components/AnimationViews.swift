import SwiftUI

struct FloatingHeartsBackground: View {
    @State private var animate = false
    private let heartSizes: [CGFloat] = (0..<10).map { _ in
        CGFloat(Int.random(in: 10...24))
    }

    var body: some View {
        GeometryReader { geo in
            let width = max(Int(geo.size.width), 1)
            let height = max(Int(geo.size.height), 1)

            ZStack {
                ForEach(0..<10, id: \.self) { index in
                    Image(systemName: index.isMultiple(of: 2) ? "heart.fill" : "heart")
                        .font(.system(size: heartSizes[index]))
                        .foregroundStyle(.white.opacity(0.08))
                        .position(
                            x: CGFloat((index * 41) % width),
                            y: animate ? CGFloat((index * 83) % height) : CGFloat((index * 37) % height)
                        )
                        .animation(
                            .easeInOut(duration: Double(8 + index)).repeatForever(autoreverses: true),
                            value: animate
                        )
                }
            }
            .onAppear { animate = true }
        }
        .allowsHitTesting(false)
    }
}

struct HeartBurstEffect: View {
    let trigger: Int
    @State private var animate = false

    var body: some View {
        ZStack {
            ForEach(0..<8, id: \.self) { index in
                let angle = Double(index) * (.pi / 4)
                let x = cos(angle) * (animate ? 58 : 0)
                let y = sin(angle) * (animate ? 58 : 0)

                Image(systemName: "heart.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(LumiTheme.Colors.blush)
                    .offset(x: x, y: y)
                    .scaleEffect(animate ? 0.1 : 1)
                    .opacity(animate ? 0 : 1)
                    .animation(.easeOut(duration: 0.55).delay(Double(index) * 0.015), value: animate)
            }
        }
        .onChange(of: trigger) { _, _ in
            animate = false
            withAnimation {
                animate = true
            }
        }
    }
}
