import SwiftUI

struct HomeView: View {
    @ObservedObject var viewModel: HomeViewModel
    @State private var showHero = false
    @State private var showPackages = false
    @State private var showFeatured = false
    @State private var showContinue = false
    @State private var heartPulse = false
    @State private var glowPulse = false
    @State private var showContinuePlaceholder = false
    @State private var featuredMessage = ""

    private let fallbackNecklaceName = "Lumi Original"
    private let fallbackPackageIDs = ["love", "motivation", "calm"]

    private var necklaceName: String {
        let equipped = viewModel.equippedLabel
        return equipped == "No necklace equipped" ? fallbackNecklaceName : equipped
    }

    private var packageIDs: [String] {
        let enabled = viewModel.enabledPackageIDs
        return enabled.isEmpty ? fallbackPackageIDs : enabled
    }

    private var packageTitles: [String] {
        packageIDs.map { id in
            switch id {
            case "love": return "Love"
            case "motivation": return "Motivation"
            case "calm": return "Calm"
            default: return id.capitalized
            }
        }
    }

    var body: some View {
        ZStack {
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
            .ignoresSafeArea()

            FloatingHeartsBackground()

            ScrollView {
                VStack(spacing: 22) {
                    HStack {
                        Text("Lumi ♥")
                            .font(.system(size: 30, weight: .light, design: .serif))
                            .foregroundStyle(Color.white.opacity(0.95))
                        Spacer()
                        Button {
                            // Minimal placeholder for future profile/settings routing.
                        } label: {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(0.72))
                                .frame(width: 34, height: 34)
                                .background(Color.white.opacity(0.08))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 8)

                    VStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.17))
                                .frame(width: 180, height: 180)
                                .blur(radius: 18)
                                .scaleEffect(glowPulse ? 1.04 : 0.96)

                            Image(systemName: "heart.fill")
                                .font(.system(size: 82, weight: .regular))
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
                                .scaleEffect(heartPulse ? 1.03 : 0.99)
                        }
                        .padding(.top, 8)

                        Text("Your Lumi is ready")
                            .font(.system(size: 42, weight: .regular, design: .serif))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Color.white.opacity(0.97))

                        Text("\(necklaceName) is linked and waiting for you.")
                            .font(.system(size: 19, weight: .regular, design: .serif))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Color.white.opacity(0.84))
                            .padding(.horizontal, 18)
                    }
                    .opacity(showHero ? 1 : 0)
                    .offset(y: showHero ? 0 : 12)
                    .animation(.easeInOut(duration: 0.7), value: showHero)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Included with your Lumi")
                            .font(.system(size: 14, weight: .regular, design: .serif))
                            .foregroundStyle(Color.white.opacity(0.76))

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(packageTitles, id: \.self) { package in
                                    PackageChip(title: package)
                                }
                            }
                        }
                    }
                    .opacity(showPackages ? 1 : 0)
                    .offset(y: showPackages ? 0 : 12)
                    .animation(.easeInOut(duration: 0.7), value: showPackages)

                    FeaturedMessageCard(message: featuredMessage)
                        .opacity(showFeatured ? 1 : 0)
                        .offset(y: showFeatured ? 0 : 12)
                        .animation(.easeInOut(duration: 0.7), value: showFeatured)

                    HStack(spacing: 10) {
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.84))
                        Text("Tap your necklace anytime")
                            .font(.system(size: 16, weight: .regular, design: .serif))
                            .foregroundStyle(Color.white.opacity(0.86))
                        Spacer()
                    }
                    .padding(14)
                    .background(Color.white.opacity(0.11))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                    if viewModel.showRetapHint {
                        Text("We couldn’t restore your last handoff details. Tap your necklace once to refresh everything.")
                            .font(.system(size: 14, weight: .regular, design: .serif))
                            .foregroundStyle(Color.white.opacity(0.80))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Color.white.opacity(0.10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    VStack(spacing: 10) {
                        Button("Continue") {
                            showContinuePlaceholder = true
                        }
                        .buttonStyle(PrimaryButtonStyle())

                        HStack(spacing: 18) {
                            Button("View collection") {}
                            Button("Explore your Lumi") {}
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 14, weight: .regular, design: .serif))
                        .foregroundStyle(Color.white.opacity(0.74))
                    }
                    .opacity(showContinue ? 1 : 0)
                    .offset(y: showContinue ? 0 : 12)
                    .animation(.easeInOut(duration: 0.7), value: showContinue)
                }
                .padding(20)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            featuredMessage = Self.pickFeaturedMessage(
                from: packageIDs,
                preferred: viewModel.message?.text
            )

            withAnimation(.easeInOut(duration: 5.2).repeatForever(autoreverses: true)) {
                heartPulse.toggle()
            }
            withAnimation(.easeInOut(duration: 6.0).repeatForever(autoreverses: true)) {
                glowPulse.toggle()
            }

            Task {
                showHero = true
                try? await Task.sleep(for: .milliseconds(140))
                showPackages = true
                try? await Task.sleep(for: .milliseconds(140))
                showFeatured = true
                try? await Task.sleep(for: .milliseconds(160))
                showContinue = true
            }
        }
        .onChange(of: packageIDs) { _, newValue in
            featuredMessage = Self.pickFeaturedMessage(
                from: newValue,
                preferred: viewModel.message?.text
            )
        }
        .alert("Coming soon", isPresented: $showContinuePlaceholder) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Continue will route deeper into the full app experience next.")
        }
    }

    private static func pickFeaturedMessage(from packageIDs: [String], preferred: String?) -> String {
        if let preferred, !preferred.isEmpty {
            return preferred
        }

        let mapped = packageIDs.compactMap { id -> [String]? in
            switch id {
            case "love":
                return [
                    "You are deeply loved, exactly as you are.",
                    "Love already lives in every step you take."
                ]
            case "motivation":
                return [
                    "Keep going. Your light is already changing things.",
                    "You are stronger than every doubt in front of you."
                ]
            case "calm":
                return [
                    "Breathe slowly. You are safe in this moment.",
                    "Quiet your mind. Your heart already knows the way."
                ]
            default:
                return nil
            }
        }
        let pool = mapped.flatMap { $0 }
        return pool.randomElement() ?? "Your Lumi is here whenever you need it."
    }
}

struct PackageChip: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 15, weight: .regular, design: .serif))
            .foregroundStyle(Color.white.opacity(0.88))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Color.white.opacity(0.14))
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.20), lineWidth: 1)
            )
            .clipShape(Capsule())
    }
}

struct FeaturedMessageCard: View {
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Featured for you")
                .font(.system(size: 14, weight: .regular, design: .serif))
                .foregroundStyle(Color.white.opacity(0.72))

            Text(message)
                .font(.system(size: 30, weight: .regular, design: .serif))
                .foregroundStyle(Color.white.opacity(0.96))
                .lineSpacing(4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            LinearGradient(
                colors: [
                    Color.white.opacity(0.18),
                    Color.white.opacity(0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.24), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color.black.opacity(0.15), radius: 12, y: 8)
    }
}
