//
//  HeartParticle.swift
//  lumiclip
//

import SwiftUI

struct HeartParticle: View {
    let xPosition: CGFloat
    let size: CGFloat
    let duration: Double
    let delay: Double
    let drift: CGFloat
    let opacity: Double

    @State private var isAnimating = false

    var body: some View {
        GeometryReader { geometry in
            Image(systemName: "heart.fill")
                .font(.system(size: size, weight: .regular))
                .foregroundStyle(Color.white.opacity(opacity))
                .position(
                    x: geometry.size.width * xPosition + (isAnimating ? drift : -drift),
                    y: isAnimating ? -size * 2 : geometry.size.height + size * 2
                )
                .scaleEffect(isAnimating ? 1.1 : 0.9)
                .blur(radius: 0.4)
                .onAppear {
                    withAnimation(
                        .easeInOut(duration: duration)
                            .delay(delay)
                            .repeatForever(autoreverses: false)
                    ) {
                        isAnimating = true
                    }
                }
        }
        .allowsHitTesting(false)
    }
}

