import SwiftUI
import UIKit

struct ClipMessageView: View {
    let activationResult: ClipActivationResult

    @EnvironmentObject private var clipModel: ClipModel

    @State private var message = ""
    @State private var showSaveScreen = false
    @State private var screenVisible = false
    @State private var heartPulse = false
    @State private var glowPulse = false

    private let particles: [MessageParticleSpec] = [
        .init(x: 0.18, size: 8, duration: 18, delay: 0.2, drift: -9, opacity: 0.06),
        .init(x: 0.38, size: 9, duration: 20, delay: 1.4, drift: 8, opacity: 0.07),
        .init(x: 0.62, size: 8, duration: 22, delay: 2.2, drift: -8, opacity: 0.06),
        .init(x: 0.84, size: 9, duration: 19, delay: 0.8, drift: 9, opacity: 0.07)
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
                    .animation(.easeInOut(duration: 0.65), value: screenVisible)

                Spacer(minLength: 20)

                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color(red: 1.0, green: 0.90, blue: 0.80).opacity(0.23),
                                    Color(red: 1.0, green: 0.90, blue: 0.80).opacity(0.0)
                                ],
                                center: .center,
                                startRadius: 4,
                                endRadius: 96
                            )
                        )
                        .frame(width: 180, height: 180)
                        .blur(radius: 12)
                        .scaleEffect(glowPulse ? 1.05 : 0.95)

                    Image(systemName: "heart.fill")
                        .font(.system(size: 76, weight: .regular))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.99, green: 0.90, blue: 0.81),
                                    Color(red: 0.91, green: 0.50, blue: 0.53),
                                    Color(red: 0.76, green: 0.20, blue: 0.33)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .scaleEffect(heartPulse ? 1.03 : 0.99)
                }
                .opacity(screenVisible ? 1 : 0)
                .offset(y: screenVisible ? 0 : 10)
                .animation(.easeInOut(duration: 0.7).delay(0.12), value: screenVisible)

                VStack(spacing: 14) {
                    Text("Your message")
                        .font(.system(size: 40, weight: .regular, design: .serif))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Color.white.opacity(0.97))

                    Text(message)
                        .font(.system(size: 28, weight: .regular, design: .serif))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Color.white.opacity(0.95))
                        .lineSpacing(5)
                        .padding(.horizontal, 26)
                }
                .padding(.top, 22)
                .opacity(screenVisible ? 1 : 0)
                .offset(y: screenVisible ? 0 : 10)
                .animation(.easeInOut(duration: 0.7).delay(0.24), value: screenVisible)

                Spacer(minLength: 0)

                VStack(spacing: 12) {
                    Button {
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.65)
                        withAnimation(.easeInOut(duration: 0.35)) {
                            message = Self.makeMessage(from: activationResult.basePackageIDs)
                        }
                    } label: {
                        Text("Show another message")
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.white.opacity(0.12))
                            .overlay(
                                Capsule()
                                    .stroke(Color.white.opacity(0.24), lineWidth: 1)
                            )
                            .clipShape(Capsule())
                    }

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
                            .shadow(color: Color.black.opacity(0.18), radius: 11, y: 7)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 26)
                .opacity(screenVisible ? 1 : 0)
                .offset(y: screenVisible ? 0 : 12)
                .animation(.easeInOut(duration: 0.65).delay(0.36), value: screenVisible)
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
        .onAppear {
            if message.isEmpty {
                message = Self.makeMessage(from: activationResult.basePackageIDs)
            }

            screenVisible = true
            startAmbientAnimations()
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
        withAnimation(.easeInOut(duration: 5.4).repeatForever(autoreverses: true)) {
            heartPulse.toggle()
        }

        withAnimation(.easeInOut(duration: 6.0).repeatForever(autoreverses: true)) {
            glowPulse.toggle()
        }
    }

    private nonisolated static func makeMessage(from packageIDs: [String]) -> String {
        let mapped = packageIDs.compactMap(mapPackageType)
        let selectedType = (mapped.isEmpty ? [.love] : mapped).randomElement() ?? .love
        return selectedType.messages.randomElement() ?? "You are loved more deeply than you know."
    }

    private nonisolated static func mapPackageType(_ id: String) -> ClipMessagePackageType? {
        let normalized = id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.contains("love") { return .love }
        if normalized.contains("motivation") { return .motivation }
        if normalized.contains("calm") { return .calm }
        return nil
    }
}

private struct MessageParticleSpec: Identifiable {
    let id = UUID()
    let x: CGFloat
    let size: CGFloat
    let duration: Double
    let delay: Double
    let drift: CGFloat
    let opacity: Double
}

private enum ClipMessagePackageType {
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
    NavigationStack {
        ClipMessageView(
            activationResult: ClipActivationResult(
                necklaceID: "TAG171867224",
                necklaceName: "Lumi Original",
                basePackageIDs: ["love", "motivation"]
            )
        )
        .environmentObject(ClipModel())
    }
}
