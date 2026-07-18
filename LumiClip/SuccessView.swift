//
//  SuccessView.swift
//  lumiclip
//

import SwiftUI
import UIKit

struct SuccessView: View {
    let activationResult: ClipActivationResult

    @EnvironmentObject private var clipModel: ClipModel

    @State private var screenVisible = false
    @State private var pendantFloat = false
    @State private var pendantBreath = false
    @State private var glowPulse = false
    @State private var revealHeartPulse = false
    @State private var revealGlowPulse = false
    @State private var showSaveScreen = false
    @State private var showMessageScreen = false
    @State private var revealContent = ""
    @State private var showCTAButtons = false

    private let particles: [SuccessParticleSpec] = [
        .init(x: 0.20, size: 8, duration: 20, delay: 0.2, drift: -10, opacity: 0.07),
        .init(x: 0.35, size: 10, duration: 22, delay: 1.0, drift: 9, opacity: 0.06),
        .init(x: 0.50, size: 9, duration: 19, delay: 2.1, drift: -9, opacity: 0.07),
        .init(x: 0.66, size: 11, duration: 24, delay: 3.0, drift: 12, opacity: 0.08),
        .init(x: 0.82, size: 8, duration: 18, delay: 1.6, drift: -10, opacity: 0.06)
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
                VStack(alignment: .leading, spacing: 6) {
                    Text("Lumi ♥")
                        .font(.system(size: 22, weight: .light, design: .serif))
                        .tracking(0.8)
                        .foregroundStyle(Color.white.opacity(0.93))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 26)
                .padding(.top, 18)
                .opacity(screenVisible ? 1 : 0)
                .offset(y: screenVisible ? 0 : 8)
                .animation(.easeInOut(duration: 0.7).delay(0.05), value: screenVisible)

                Spacer(minLength: 12)

                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color(red: 1.0, green: 0.92, blue: 0.80).opacity(0.36),
                                    Color(red: 1.0, green: 0.92, blue: 0.80).opacity(0.0)
                                ],
                                center: .center,
                                startRadius: 4,
                                endRadius: 120
                            )
                        )
                        .frame(width: 234, height: 234)
                        .blur(radius: 12)
                        .scaleEffect(glowPulse ? 1.08 : 0.94)

                    pendantImage
                        .frame(width: 146, height: 164)
                        .scaleEffect(pendantBreath ? 1.03 : 0.97)
                        .offset(y: pendantFloat ? -5 : 6)
                }
                .opacity(screenVisible ? 1 : 0)
                .offset(y: screenVisible ? 0 : 14)
                .animation(.easeInOut(duration: 0.72).delay(0.25), value: screenVisible)

                Text("Your \(activationResult.necklaceName)\nis unlocked")
                    .font(.system(size: 34, weight: .regular, design: .serif))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.white.opacity(0.97))
                    .lineSpacing(2)
                    .lineLimit(2)
                    .minimumScaleFactor(0.60)
                    .allowsTightening(true)
                .padding(.horizontal, 26)
                .frame(maxWidth: .infinity)
                .opacity(screenVisible ? 1 : 0)
                .offset(y: screenVisible ? 0 : 10)
                .animation(.easeInOut(duration: 0.72).delay(0.36), value: screenVisible)
                .padding(.top, 14)

                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.13))
                        .frame(width: 180, height: 180)
                        .blur(radius: 20)
                        .scaleEffect(revealGlowPulse ? 1.10 : 0.94)

                    Image(systemName: "heart.fill")
                        .font(.system(size: 110, weight: .regular))
                        .foregroundStyle(Color.white.opacity(0.08))
                        .scaleEffect(revealHeartPulse ? 1.05 : 1.0)

                    VStack(spacing: 12) {
                        Text(revealContent)
                            .font(.system(size: 28, weight: .regular, design: .serif))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Color.white.opacity(0.96))
                            .lineSpacing(4)
                            .padding(.horizontal, 28)
                            .padding(.vertical, 10)

                        Text("This is now yours")
                            .font(.system(size: 17, weight: .regular, design: .serif))
                            .foregroundStyle(Color.white.opacity(0.90))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 30)
                .opacity(screenVisible ? 1 : 0)
                .offset(y: screenVisible ? 0 : 10)
                .animation(.easeInOut(duration: 0.72).delay(0.62), value: screenVisible)

                Spacer(minLength: 0)

                VStack(spacing: 12) {
                    Button {
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.7)
                        showSaveScreen = true
                    } label: {
                        Text("Save your Lumi")
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

                    Button("Maybe later") {
                        showMessageScreen = true
                    }
                    .font(.system(size: 16, weight: .regular, design: .serif))
                    .foregroundStyle(Color.white.opacity(0.80))
                }
                .padding(.horizontal, 28)
                .padding(.top, 22)
                .padding(.bottom, 26)
                .opacity(showCTAButtons ? 1 : 0)
                .scaleEffect(showCTAButtons ? 1 : 0.95)
                .animation(.easeInOut(duration: 0.58), value: showCTAButtons)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .navigationDestination(isPresented: $showSaveScreen) {
            SaveLumiView(
                necklaceName: activationResult.necklaceName,
                tagId: activationResult.necklaceID ?? clipModel.nfcID ?? "TAG171867224",
                basePackageIDs: activationResult.basePackageIDs
            )
        }
        .navigationDestination(isPresented: $showMessageScreen) {
            ClipMessageView(activationResult: activationResult)
        }
        .onAppear {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.45)
            revealContent = Self.makeRevealContent(from: activationResult.basePackageIDs)
            screenVisible = true
            startAmbientAnimations()
            Task {
                try? await Task.sleep(for: .seconds(2))
                await MainActor.run {
                    showCTAButtons = true
                }
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

    private var pendantImage: some View {
        Group {
            if let image = UIImage(named: "heart-pendant") {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "heart.fill")
                    .font(.system(size: 96, weight: .regular))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color(red: 0.99, green: 0.90, blue: 0.82),
                                Color(red: 0.90, green: 0.47, blue: 0.50),
                                Color(red: 0.73, green: 0.17, blue: 0.29)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: Color.white.opacity(0.26), radius: 9)
            }
        }
    }

    private func startAmbientAnimations() {
        withAnimation(.easeInOut(duration: 5.4).repeatForever(autoreverses: true)) {
            pendantFloat.toggle()
        }

        withAnimation(.easeInOut(duration: 4.8).repeatForever(autoreverses: true)) {
            pendantBreath.toggle()
        }

        withAnimation(.easeInOut(duration: 4.0).repeatForever(autoreverses: true)) {
            glowPulse.toggle()
        }

        withAnimation(.easeInOut(duration: 4.6).repeatForever(autoreverses: true)) {
            revealHeartPulse.toggle()
        }

        withAnimation(.easeInOut(duration: 5.2).repeatForever(autoreverses: true)) {
            revealGlowPulse.toggle()
        }
    }

    private nonisolated static func makeRevealContent(from packageIDs: [String]) -> String {
        let mapped = packageIDs.compactMap(mapPackageType)
        let selectedType = (mapped.isEmpty ? [.love] : mapped).randomElement() ?? .love
        return selectedType.messages.randomElement() ?? "You unlocked something just for your heart."
    }

    private nonisolated static func mapPackageType(_ id: String) -> RevealPackageType? {
        let normalized = id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.contains("love") { return .love }
        if normalized.contains("motivation") { return .motivation }
        if normalized.contains("calm") { return .calm }
        return nil
    }
}

private struct SuccessParticleSpec: Identifiable {
    let id = UUID()
    let x: CGFloat
    let size: CGFloat
    let duration: Double
    let delay: Double
    let drift: CGFloat
    let opacity: Double
}

private enum RevealPackageType {
    case love
    case motivation
    case calm

    nonisolated var messages: [String] {
        switch self {
        case .love:
            return [
                "You are deeply loved, exactly as you are.",
                "Love already lives in every step you take.",
                "Your heart is a home for something beautiful."
            ]
        case .motivation:
            return [
                "You are stronger than every doubt in front of you.",
                "Keep going, your light is already changing things.",
                "Today is another chance to become who you imagine."
            ]
        case .calm:
            return [
                "Breathe slowly. You are safe in this moment.",
                "Let your shoulders soften. Peace is here now.",
                "Quiet your mind. Your heart already knows the way."
            ]
        }
    }
}

#Preview {
    let clipModel = ClipModel()
    clipModel.nfcID = "TAG171867224"
    return NavigationStack {
        SuccessView(
            activationResult: ClipActivationResult(
                necklaceID: "tag-123",
                necklaceName: "Lumi Original",
                basePackageIDs: ["love", "calm"]
            )
        )
        .environmentObject(clipModel)
    }
}
