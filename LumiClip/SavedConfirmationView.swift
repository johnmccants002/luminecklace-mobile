//
//  SavedConfirmationView.swift
//  lumiclip
//

import SwiftUI
import UIKit

struct SavedConfirmationView: View {
    // TODO: Replace this placeholder with real install-detection logic.
    let isFullAppInstalled: Bool
    let necklaceName: String
    let tagId: String
    let basePackageIDs: [String]

    @Environment(\.dismiss) private var dismiss

    @State private var screenVisible = false
    @State private var showTitle = false
    @State private var showBody = false
    @State private var showBenefits = false
    @State private var showActions = false
    @State private var heartPulse = false
    @State private var glowPulse = false
    @State private var ringPulse = false
    @State private var ringDraw: CGFloat = 0
    @State private var showCheckmark = false
    @State private var showHandoffPlaceholder = false

    private let particles: [SavedParticleSpec] = [
        .init(x: 0.18, size: 7, duration: 21, delay: 0.3, drift: -8, opacity: 0.05),
        .init(x: 0.44, size: 8, duration: 23, delay: 1.7, drift: 7, opacity: 0.05),
        .init(x: 0.72, size: 7, duration: 20, delay: 2.9, drift: -8, opacity: 0.05)
    ]

    private var primaryButtonTitle: String {
        isFullAppInstalled ? "Open full app" : "Get the full app"
    }

    init(
        isFullAppInstalled: Bool,
        necklaceName: String = "Lumi Original",
        tagId: String = "TAG171867224",
        basePackageIDs: [String] = ["love", "motivation", "calm"]
    ) {
        self.isFullAppInstalled = isFullAppInstalled
        self.necklaceName = necklaceName
        self.tagId = tagId
        self.basePackageIDs = basePackageIDs
    }

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

                Spacer(minLength: 26)

                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color(red: 1.0, green: 0.92, blue: 0.82).opacity(0.20),
                                    Color(red: 1.0, green: 0.92, blue: 0.82).opacity(0.0)
                                ],
                                center: .center,
                                startRadius: 2,
                                endRadius: 92
                            )
                        )
                        .frame(width: 180, height: 180)
                        .blur(radius: 12)
                        .scaleEffect(glowPulse ? 1.04 : 0.96)

                    Circle()
                        .trim(from: 0, to: ringDraw)
                        .stroke(Color.white.opacity(0.55), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                        .frame(width: 112, height: 112)
                        .rotationEffect(.degrees(-90))
                        .scaleEffect(ringPulse ? 1.02 : 0.98)

                    Image(systemName: "heart.fill")
                        .font(.system(size: 72, weight: .regular))
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

                    Image(systemName: "checkmark")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.92))
                        .offset(x: 38, y: -34)
                        .opacity(showCheckmark ? 1 : 0)
                        .scaleEffect(showCheckmark ? 1 : 0.85)
                }
                .opacity(screenVisible ? 1 : 0)
                .offset(y: screenVisible ? 0 : 10)
                .animation(.easeInOut(duration: 0.7).delay(0.12), value: screenVisible)

                VStack(spacing: 13) {
                    Text("Saved to your account")
                        .font(.system(size: 41, weight: .regular, design: .serif))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Color.white.opacity(0.97))
                        .opacity(showTitle ? 1 : 0)
                        .offset(y: showTitle ? 0 : 10)
                        .animation(.easeInOut(duration: 0.65), value: showTitle)

                    VStack(spacing: 9) {
                        Text("Your Lumi is now linked and ready whenever you are.")
                            .font(.system(size: 20, weight: .regular, design: .serif))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Color.white.opacity(0.87))
                            .lineSpacing(3)

                        Text("Open the full app to keep it with you, explore your collection, and come back anytime.")
                            .font(.system(size: 16, weight: .regular, design: .serif))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Color.white.opacity(0.78))
                            .lineSpacing(3)
                    }
                    .padding(.horizontal, 28)
                    .opacity(showBody ? 1 : 0)
                    .offset(y: showBody ? 0 : 10)
                    .animation(.easeInOut(duration: 0.65), value: showBody)

                    VStack(spacing: 6) {
                        benefitRow("Keep your Lumi linked")
                        benefitRow("Access your collection anytime")
                        benefitRow("Return with a tap")
                    }
                    .padding(.top, 8)
                    .opacity(showBenefits ? 1 : 0)
                    .offset(y: showBenefits ? 0 : 8)
                    .animation(.easeInOut(duration: 0.65), value: showBenefits)
                }
                .padding(.top, 24)

                Spacer(minLength: 0)

                VStack(spacing: 12) {
                    Button {
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.7)
                        handleOpenOrInstallFullApp()
                    } label: {
                        Text(primaryButtonTitle)
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

                    Button("Stay here for now") {
                        dismiss()
                    }
                    .font(.system(size: 16, weight: .regular, design: .serif))
                    .foregroundStyle(Color.white.opacity(0.80))
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 26)
                .opacity(showActions ? 1 : 0)
                .offset(y: showActions ? 0 : 10)
                .animation(.easeInOut(duration: 0.65), value: showActions)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.45)
            screenVisible = true
            startAmbientAnimations()

            withAnimation(.easeInOut(duration: 0.9)) {
                ringDraw = 1
            }
            withAnimation(.easeInOut(duration: 0.45).delay(0.42)) {
                showCheckmark = true
            }

            Task {
                try? await Task.sleep(for: .milliseconds(130))
                await MainActor.run { showTitle = true }
                try? await Task.sleep(for: .milliseconds(130))
                await MainActor.run { showBody = true }
                try? await Task.sleep(for: .milliseconds(140))
                await MainActor.run { showBenefits = true }
                try? await Task.sleep(for: .milliseconds(170))
                await MainActor.run { showActions = true }
            }
        }
        .alert("Coming soon", isPresented: $showHandoffPlaceholder) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Full app handoff will be connected next.")
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

    private func benefitRow(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "heart.fill")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.64))
            Text(text)
                .font(.system(size: 14, weight: .regular, design: .serif))
                .foregroundStyle(Color.white.opacity(0.78))
        }
    }

    private func startAmbientAnimations() {
        withAnimation(.easeInOut(duration: 5.6).repeatForever(autoreverses: true)) {
            heartPulse.toggle()
        }

        withAnimation(.easeInOut(duration: 6.2).repeatForever(autoreverses: true)) {
            glowPulse.toggle()
        }

        withAnimation(.easeInOut(duration: 5.0).repeatForever(autoreverses: true)) {
            ringPulse.toggle()
        }
    }

    private func handleOpenOrInstallFullApp() {
        let payload = ClipHandoffPayload(
            necklaceName: necklaceName,
            tagId: tagId,
            basePackageIDs: basePackageIDs,
            completedAt: Date()
        )
        let handoffID = ClipHandoffStore().createHandoff(payload: payload)

        // TODO: Keep this URL contract in sync with the full app handoff parser.
        guard let universalURL = makeUniversalHandoffURL(handoffID: handoffID) else {
            showHandoffPlaceholder = true
            return
        }

        if isFullAppInstalled {
            UIApplication.shared.open(universalURL) { success in
                if success { return }

                if let fallbackURL = self.makeSchemeHandoffURL(handoffID: handoffID) {
                    UIApplication.shared.open(fallbackURL) { fallbackOpened in
                        if !fallbackOpened {
                            self.openAppStoreFallback()
                        }
                    }
                } else {
                    self.openAppStoreFallback()
                }
            }
        } else {
            openAppStoreFallback()
        }
    }

    private func makeUniversalHandoffURL(handoffID: String) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.luminecklace.com"
        components.path = "/handoff"
        components.queryItems = [
            URLQueryItem(name: "h", value: handoffID),
            URLQueryItem(name: "src", value: "clip")
        ]
        return components.url
    }

    private func makeSchemeHandoffURL(handoffID: String) -> URL? {
        var components = URLComponents()
        components.scheme = "luminecklace"
        components.host = "handoff"
        components.path = "/\(handoffID)"
        components.queryItems = [URLQueryItem(name: "src", value: "clip")]
        return components.url
    }

    private func openAppStoreFallback() {
        let fallbackURLs = [
            "itms-apps://apps.apple.com/app/id6761403318",
            "https://apps.apple.com/app/id6761403318"
        ].compactMap(URL.init(string:))

        guard !fallbackURLs.isEmpty else {
            showHandoffPlaceholder = true
            return
        }

        openFallbackURL(at: 0, urls: fallbackURLs)
    }

    private func openFallbackURL(at index: Int, urls: [URL]) {
        guard urls.indices.contains(index) else {
            showHandoffPlaceholder = true
            return
        }

        UIApplication.shared.open(urls[index]) { opened in
            if opened {
                return
            }

            self.openFallbackURL(at: index + 1, urls: urls)
        }
    }
}

private struct SavedParticleSpec: Identifiable {
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
        SavedConfirmationView(
            isFullAppInstalled: false,
            necklaceName: "Lumi Original",
            tagId: "TAG171867224",
            basePackageIDs: ["love", "motivation", "calm"]
        )
    }
}
