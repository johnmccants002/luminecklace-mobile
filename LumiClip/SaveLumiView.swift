//
//  SaveLumiView.swift
//  lumiclip
//

import SwiftUI
import UIKit

struct SaveLumiView: View {
    let necklaceName: String
    let tagId: String
    let basePackageIDs: [String]
    let isFullAppInstalled: Bool = true

    @Environment(\.dismiss) private var dismiss

    @State private var screenVisible = false
    @State private var showTitle = false
    @State private var showSubtext = false
    @State private var showActions = false
    @State private var heartPulse = false
    @State private var glowPulse = false
    @State private var heartFloat = false
    @State private var showSavedConfirmation = false

    private let particles: [SaveParticleSpec] = [
        .init(x: 0.17, size: 8, duration: 20, delay: 0.5, drift: -8, opacity: 0.06),
        .init(x: 0.39, size: 7, duration: 18, delay: 2.0, drift: 7, opacity: 0.05),
        .init(x: 0.62, size: 9, duration: 22, delay: 1.2, drift: -9, opacity: 0.06),
        .init(x: 0.84, size: 8, duration: 19, delay: 2.8, drift: 8, opacity: 0.05)
    ]

    var body: some View {
        ZStack {
            backgroundGradient
                .ignoresSafeArea()

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

            VStack(spacing: 0) {
                Text("Lumi ♥")
                    .font(.system(size: 22, weight: .light, design: .serif))
                    .tracking(0.8)
                    .foregroundStyle(Color.white.opacity(0.93))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 26)
                    .padding(.top, 18)
                    .opacity(screenVisible ? 1 : 0)
                    .offset(y: screenVisible ? 0 : 8)
                    .animation(.easeInOut(duration: 0.7), value: screenVisible)

                Spacer(minLength: 24)

                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color(red: 1.0, green: 0.90, blue: 0.80).opacity(0.24),
                                    Color(red: 1.0, green: 0.90, blue: 0.80).opacity(0.0)
                                ],
                                center: .center,
                                startRadius: 2,
                                endRadius: 100
                            )
                        )
                        .frame(width: 190, height: 190)
                        .blur(radius: 14)
                        .scaleEffect(glowPulse ? 1.06 : 0.94)

                    Image(systemName: "heart.fill")
                        .font(.system(size: 84, weight: .regular))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.99, green: 0.89, blue: 0.79),
                                    Color(red: 0.91, green: 0.51, blue: 0.53),
                                    Color(red: 0.75, green: 0.18, blue: 0.31)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .scaleEffect(heartPulse ? 1.05 : 1.0)
                        .offset(y: heartFloat ? -4 : 4)
                }
                .opacity(screenVisible ? 1 : 0)
                .animation(.easeInOut(duration: 0.7).delay(0.15), value: screenVisible)

                VStack(spacing: 14) {
                    Text("Keep this with you")
                        .font(.system(size: 42, weight: .regular, design: .serif))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Color.white.opacity(0.97))
                        .opacity(showTitle ? 1 : 0)
                        .offset(y: showTitle ? 0 : 10)
                        .animation(.easeInOut(duration: 0.65), value: showTitle)

                    Text("Save your Lumi so it’s always yours, even if you change devices.")
                        .font(.system(size: 19, weight: .regular, design: .serif))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Color.white.opacity(0.86))
                        .lineSpacing(3)
                        .padding(.horizontal, 28)
                        .opacity(showSubtext ? 1 : 0)
                        .offset(y: showSubtext ? 0 : 10)
                        .animation(.easeInOut(duration: 0.65), value: showSubtext)
                }
                .padding(.top, 28)

                Spacer(minLength: 0)

                VStack(spacing: 12) {
                    Button {
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.65)
                        handleAppleSignIn()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "applelogo")
                                .font(.system(size: 20, weight: .semibold))
                            Text("Continue with Apple")
                                .font(.system(size: 19, weight: .semibold, design: .rounded))
                        }
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
                        .shadow(color: Color.black.opacity(0.19), radius: 12, y: 8)
                    }

                    Button("Maybe later") {
                        dismiss()
                    }
                    .font(.system(size: 16, weight: .regular, design: .serif))
                    .foregroundStyle(Color.white.opacity(0.80))
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 26)
                .opacity(showActions ? 1 : 0)
                .offset(y: showActions ? 0 : 12)
                .animation(.easeInOut(duration: 0.65), value: showActions)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .navigationDestination(isPresented: $showSavedConfirmation) {
            SavedConfirmationView(
                isFullAppInstalled: isFullAppInstalled,
                necklaceName: necklaceName,
                tagId: tagId,
                basePackageIDs: basePackageIDs
            )
        }
        .onAppear {
            screenVisible = true
            startAmbientAnimations()

            Task {
                try? await Task.sleep(for: .milliseconds(140))
                await MainActor.run { showTitle = true }
                try? await Task.sleep(for: .milliseconds(130))
                await MainActor.run { showSubtext = true }
                try? await Task.sleep(for: .milliseconds(170))
                await MainActor.run { showActions = true }
            }
        }
    }

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color(red: 0.28, green: 0.10, blue: 0.18),
                Color(red: 0.50, green: 0.27, blue: 0.33),
                Color(red: 0.85, green: 0.74, blue: 0.64),
                Color(red: 0.95, green: 0.88, blue: 0.75)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func startAmbientAnimations() {
        withAnimation(.easeInOut(duration: 4.6).repeatForever(autoreverses: true)) {
            heartPulse.toggle()
        }

        withAnimation(.easeInOut(duration: 5.4).repeatForever(autoreverses: true)) {
            glowPulse.toggle()
        }

        withAnimation(.easeInOut(duration: 5.0).repeatForever(autoreverses: true)) {
            heartFloat.toggle()
        }
    }

    private func handleAppleSignIn() {
        // TODO: replace with real Sign in with Apple completion callback.
        showSavedConfirmation = true
    }
}

private struct SaveParticleSpec: Identifiable {
    let id = UUID()
    let x: CGFloat
    let size: CGFloat
    let duration: Double
    let delay: Double
    let drift: CGFloat
    let opacity: Double
}

#Preview {
    NavigationStack {
        SaveLumiView(
            necklaceName: "Lumi Original",
            tagId: "TAG171867224",
            basePackageIDs: ["love", "motivation", "calm"]
        )
    }
}
