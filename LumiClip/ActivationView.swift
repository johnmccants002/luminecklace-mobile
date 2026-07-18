//
//  ActivationView.swift
//  lumiclip
//

import SwiftUI

struct ActivationView: View {
    @State private var activationCode = ""
    @State private var inlineError: String?
    @State private var activationResult: ClipActivationResult?
    @State private var restoredActivationResult: ClipActivationResult?
    @State private var screenVisible = false
    @State private var isValidating = false

    private let activationService = ClipActivationService()
    private let redemptionStore = ClipRedemptionStore()

    private let particles: [ActivationParticleSpec] = [
        .init(x: 0.18, size: 9, duration: 20, delay: 0.2, drift: -12, opacity: 0.07),
        .init(x: 0.34, size: 8, duration: 17, delay: 1.8, drift: 11, opacity: 0.06),
        .init(x: 0.58, size: 10, duration: 22, delay: 0.9, drift: -10, opacity: 0.08),
        .init(x: 0.74, size: 9, duration: 18, delay: 2.1, drift: 10, opacity: 0.07),
        .init(x: 0.88, size: 11, duration: 23, delay: 3.0, drift: -13, opacity: 0.08)
    ]

    var body: some View {
        ZStack {
            backgroundGradient
                .ignoresSafeArea()

            particleLayer
            contentLayer
        }
        .onAppear {
            screenVisible = true
            routeRedeemedUserIfNeeded()
        }
        .navigationTitle("Activation")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .navigationDestination(item: $activationResult) { result in
            SuccessView(activationResult: result)
        }
        .navigationDestination(item: $restoredActivationResult) { result in
            ClipMessageView(activationResult: result)
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
        VStack {
            Spacer(minLength: 28)
            activationCard
            Spacer(minLength: 0)
        }
    }

    private var activationCard: some View {
        VStack(spacing: 18) {
            headerSection
            codeEntrySection
            continueButton
        }
        .padding(22)
        .background(Color.black.opacity(0.18))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.20), radius: 14, y: 10)
        .padding(.horizontal, 22)
        .opacity(screenVisible ? 1 : 0)
        .offset(y: screenVisible ? 0 : 12)
        .animation(.easeInOut(duration: 0.65), value: screenVisible)
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Unlock your necklace")
                .font(.system(size: 36, weight: .regular, design: .serif))
                .foregroundStyle(Color.white.opacity(0.96))
            Text("Enter your activation code to continue.")
                .font(.system(size: 17, weight: .regular, design: .serif))
                .foregroundStyle(Color.white.opacity(0.84))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var codeEntrySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Activation code", text: $activationCode)
                .onChange(of: activationCode) { _, newValue in
                    let formatted = Self.formatActivationCode(newValue)
                    if formatted != newValue {
                        activationCode = formatted
                    }
                }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundStyle(.white)
                .padding(14)
                .background(Color.white.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.20), lineWidth: 1)
                )

            if let inlineError {
                Text(inlineError)
                    .font(.footnote)
                    .foregroundStyle(Color(red: 1.0, green: 0.82, blue: 0.82))
            }
        }
    }

    private var continueButton: some View {
        Button {
            Task { await activateCode() }
        } label: {
            HStack(spacing: 10) {
                if isValidating {
                    ProgressView()
                        .tint(.white)
                }
                Text(isValidating ? "Validating..." : "Continue")
            }
        }
        .font(.system(size: 18, weight: .semibold, design: .rounded))
        .buttonStyle(.borderedProminent)
        .tint(Color(red: 0.74, green: 0.17, blue: 0.30))
        .frame(maxWidth: .infinity, alignment: .leading)
        .disabled(isValidating)
    }

    @MainActor
    private func activateCode() async {
        let trimmed = activationCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            inlineError = "Please enter an activation code."
            return
        }

        inlineError = nil
        isValidating = true
        defer { isValidating = false }

        do {
            let result = try await activationService.validate(code: Self.canonicalActivationCode(from: trimmed))
            redemptionStore.save(result)
            activationResult = result
        } catch {
            inlineError = error.localizedDescription
        }
    }

    private func routeRedeemedUserIfNeeded() {
        guard activationResult == nil else { return }
        guard restoredActivationResult == nil else { return }
        guard let storedActivation = redemptionStore.load() else { return }
        restoredActivationResult = storedActivation
    }

    private static func formatActivationCode(_ input: String) -> String {
        let raw = String(input.uppercased().filter { $0.isLetter || $0.isNumber })
        guard !raw.isEmpty else { return "" }

        if raw.hasPrefix("LUMI") {
            let suffix = String(raw.dropFirst(4))
            guard !suffix.isEmpty else { return "LUMI" }
            return "LUMI-" + suffix
        }

        return grouped(raw, by: 4)
    }

    private static func canonicalActivationCode(from input: String) -> String {
        let raw = String(input.uppercased().filter { $0.isLetter || $0.isNumber })
        guard !raw.isEmpty else { return "" }

        if raw.hasPrefix("LUMI") {
            let suffix = String(raw.dropFirst(4))
            return suffix.isEmpty ? "LUMI" : "LUMI-\(suffix)"
        }

        return raw
    }

    private static func grouped(_ value: String, by size: Int) -> String {
        var output: [String] = []
        var current = ""

        for char in value {
            current.append(char)
            if current.count == size {
                output.append(current)
                current = ""
            }
        }

        if !current.isEmpty {
            output.append(current)
        }

        return output.joined(separator: "-")
    }
}

private struct ActivationParticleSpec: Identifiable {
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
        ActivationView()
    }
}
