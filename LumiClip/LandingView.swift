//
//  LandingView.swift
//  lumiclip
//

import SwiftUI
import UIKit

struct LandingView: View {
    @State private var screenVisible = false
    @State private var navigateToActivation = false
    @State private var restoredActivationResult: ClipActivationResult?
    @State private var pendantFloat = false
    @State private var pendantBreath = false
    @State private var glowPulse = false

    private let redemptionStore = ClipRedemptionStore()

    private let particles: [ParticleSpec] = [
        .init(x: 0.14, size: 11, duration: 18, delay: 0.0, drift: -16, opacity: 0.08),
        .init(x: 0.26, size: 9, duration: 16, delay: 1.6, drift: 14, opacity: 0.07),
        .init(x: 0.38, size: 12, duration: 21, delay: 3.2, drift: -18, opacity: 0.08),
        .init(x: 0.52, size: 8, duration: 15, delay: 2.4, drift: 10, opacity: 0.06),
        .init(x: 0.66, size: 10, duration: 19, delay: 0.8, drift: -12, opacity: 0.07),
        .init(x: 0.79, size: 12, duration: 22, delay: 4.0, drift: 18, opacity: 0.09),
        .init(x: 0.90, size: 9, duration: 17, delay: 2.8, drift: -14, opacity: 0.07)
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundGradient
                    .ignoresSafeArea()

                particleLayer

                contentLayer
            }
            .opacity(screenVisible ? 1 : 0)
            .onAppear {
                screenVisible = true
                startAmbientAnimations()
                resumeRedeemedFlowIfNeeded()
            }
            .navigationDestination(isPresented: $navigateToActivation) {
                ActivationView()
            }
            .navigationDestination(item: $restoredActivationResult) { result in
                ClipMessageView(activationResult: result)
            }
        }
    }

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color(red: 0.30, green: 0.10, blue: 0.18),
                Color(red: 0.59, green: 0.33, blue: 0.34),
                Color(red: 0.89, green: 0.78, blue: 0.66),
                Color(red: 0.96, green: 0.89, blue: 0.73)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var particleLayer: some View {
        ZStack {
            ForEach(particles) { particle in
                HeartParticle(
                    xPosition: particle.x,
                    size: particle.size,
                    duration: particle.duration,
                    delay: particle.delay,
                    drift: particle.drift,
                    opacity: particle.opacity
                )
            }
        }
        .ignoresSafeArea()
    }

    private var contentLayer: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 28)

            VStack(spacing: 18) {
                Text("Lumi ♥")
                    .font(.system(size: 22, weight: .light, design: .serif))
                    .tracking(0.8)
                    .foregroundStyle(Color.white.opacity(0.92))
                    .opacity(screenVisible ? 1 : 0)
                    .offset(y: screenVisible ? 0 : 8)
                    .animation(.easeInOut(duration: 0.7).delay(0.05), value: screenVisible)

                Text("Tap Into Love")
                    .font(.system(size: 52, weight: .regular, design: .serif))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.white.opacity(0.96))
                    .lineSpacing(2)
                    .opacity(screenVisible ? 1 : 0)
                    .offset(y: screenVisible ? 0 : 16)
                    .animation(.easeInOut(duration: 0.72).delay(0.18), value: screenVisible)

                Text("A necklace that holds something just for you.")
                    .font(.system(size: 18, weight: .regular, design: .serif))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.white.opacity(0.86))
                    .padding(.horizontal, 24)
                    .opacity(screenVisible ? 1 : 0)
                    .offset(y: screenVisible ? 0 : 10)
                    .animation(.easeInOut(duration: 0.7).delay(0.34), value: screenVisible)

                pendantView
                    .padding(.top, 24)
                    .opacity(screenVisible ? 1 : 0)
                    .offset(y: screenVisible ? 0 : 14)
                    .animation(.easeInOut(duration: 0.76).delay(0.5), value: screenVisible)
            }
            .offset(y: -28)
            .frame(maxWidth: .infinity)

            Spacer()

            Button {
                UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.6)
                continueFlow()
            } label: {
                Text("Continue")
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 17)
                    .background(
                        LinearGradient(
                            colors: [
                                Color(red: 0.83, green: 0.27, blue: 0.37),
                                Color(red: 0.70, green: 0.10, blue: 0.22)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(Capsule())
                    .shadow(color: Color.black.opacity(0.20), radius: 12, y: 8)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 34)
            .opacity(screenVisible ? 1 : 0)
            .scaleEffect(screenVisible ? 1 : 0.95)
            .animation(.easeInOut(duration: 0.72).delay(0.68), value: screenVisible)
        }
    }

    private var pendantView: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 1.0, green: 0.90, blue: 0.78).opacity(0.38),
                            Color(red: 1.0, green: 0.90, blue: 0.78).opacity(0.0)
                        ],
                        center: .center,
                        startRadius: 4,
                        endRadius: 120
                    )
                )
                .frame(width: 230, height: 230)
                .blur(radius: 14)
                .scaleEffect(glowPulse ? 1.08 : 0.92)

            pendantImage
                .frame(width: 152, height: 172)
                .scaleEffect(pendantBreath ? 1.03 : 0.97)
                .offset(y: pendantFloat ? -6 : 7)
        }
    }

    private var pendantImage: some View {
        Group {
            if let image = UIImage(named: "heart-pendant") {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 54, style: .continuous)
                        .fill(Color.white.opacity(0.12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 54, style: .continuous)
                                .stroke(Color.white.opacity(0.24), lineWidth: 1)
                        )

                    Image(systemName: "heart.fill")
                        .font(.system(size: 78, weight: .regular))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.99, green: 0.88, blue: 0.78),
                                    Color(red: 0.90, green: 0.47, blue: 0.50),
                                    Color(red: 0.73, green: 0.17, blue: 0.29)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .shadow(color: Color.white.opacity(0.28), radius: 8)
                }
            }
        }
    }

    private func continueFlow() {
        if let storedActivation = redemptionStore.load() {
            restoredActivationResult = storedActivation
            return
        }

        navigateToActivation = true
    }

    private func resumeRedeemedFlowIfNeeded() {
        guard restoredActivationResult == nil else { return }
        guard let storedActivation = redemptionStore.load() else { return }
        restoredActivationResult = storedActivation
    }

    private func startAmbientAnimations() {
        withAnimation(.easeInOut(duration: 5.2).repeatForever(autoreverses: true)) {
            pendantFloat.toggle()
        }

        withAnimation(.easeInOut(duration: 4.6).repeatForever(autoreverses: true)) {
            pendantBreath.toggle()
        }

        withAnimation(.easeInOut(duration: 3.8).repeatForever(autoreverses: true)) {
            glowPulse.toggle()
        }
    }
}

private struct ParticleSpec: Identifiable {
    let id = UUID()
    let x: CGFloat
    let size: CGFloat
    let duration: Double
    let delay: Double
    let drift: CGFloat
    let opacity: Double
}

#Preview {
    LandingView()
}
