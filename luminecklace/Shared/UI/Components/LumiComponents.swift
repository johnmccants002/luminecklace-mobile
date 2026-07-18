import SwiftUI

struct LumiTextField: View {
    let label: String
    @Binding var text: String
    var secure: Bool = false
    var keyboardType: UIKeyboardType = .default
    var autocapitalization: TextInputAutocapitalization = .never

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(LumiTheme.Typography.body(14).weight(.medium))
                .foregroundStyle(.white.opacity(0.9))

            Group {
                if secure {
                    SecureField(label, text: $text)
                } else {
                    TextField(label, text: $text)
                        .textInputAutocapitalization(autocapitalization)
                }
            }
            .keyboardType(keyboardType)
            .foregroundStyle(.white)
            .padding(14)
            .background(LumiTheme.Colors.ink.opacity(0.34))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(.white.opacity(0.24), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}

struct PrimaryButton: View {
    let title: String
    var isLoading: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if isLoading {
                    ProgressView().tint(.white)
                }
                Text(title)
            }
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(isLoading)
    }
}

struct MessageCardView: View {
    let message: Message?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Tap Experience", systemImage: "sparkles")
                .font(LumiTheme.Typography.body(13).weight(.medium))
                .foregroundStyle(.white.opacity(0.9))

            Text(message?.text ?? "Tap your necklace to reveal a message.")
                .font(LumiTheme.Typography.headline(28))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let message {
                Text(message.packageId.capitalized)
                    .font(LumiTheme.Typography.body(13))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.18))
                    .clipShape(Capsule())
                    .foregroundStyle(.white)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
}

struct NecklaceCardView: View {
    let necklace: NecklaceTag

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "heart.circle.fill")
                    .foregroundStyle(.white)
                Spacer()
                if necklace.isEquipped {
                    Text("Equipped")
                        .font(LumiTheme.Typography.body(11).weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.white.opacity(0.22))
                        .clipShape(Capsule())
                }
            }
            Text(necklace.name)
                .font(LumiTheme.Typography.body(15).weight(.semibold))
                .foregroundStyle(.white)
            Text(necklace.themeKey.capitalized + " Theme")
                .font(LumiTheme.Typography.body(12))
                .foregroundStyle(.white.opacity(0.85))
            if let rarity = necklace.rarity {
                Text(rarity)
                    .font(LumiTheme.Typography.body(11).weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(LumiTheme.Colors.blush.opacity(0.9))
                    .foregroundStyle(LumiTheme.Colors.ink)
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 130)
        .glassCard()
    }
}

struct PackageRowView: View {
    let package: Package
    let canEnable: Bool
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(package.title)
                        .font(LumiTheme.Typography.body(16).weight(.semibold))
                        .foregroundStyle(.white)
                    if package.isPremium {
                        Image(systemName: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(LumiTheme.Colors.blush)
                    }
                }
                Text(package.isPremium ? "Premium package" : "Included")
                    .font(LumiTheme.Typography.body(12))
                    .foregroundStyle(.white.opacity(0.75))
            }
            Spacer()
            Toggle("", isOn: Binding(get: {
                package.isEnabled
            }, set: { newValue in
                onToggle(newValue)
            }))
            .labelsHidden()
            .disabled(!canEnable)
        }
        .glassCard()
    }
}

struct EmptyStateView: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 34))
                .foregroundStyle(.white.opacity(0.8))
            Text(title)
                .font(LumiTheme.Typography.headline(20))
                .foregroundStyle(.white)
            Text(subtitle)
                .font(LumiTheme.Typography.body(14))
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .glassCard()
    }
}

struct LoadingOverlay: View {
    let isVisible: Bool

    var body: some View {
        if isVisible {
            ZStack {
                Color.black.opacity(0.3).ignoresSafeArea()
                ProgressView("Loading...")
                    .tint(.white)
                    .padding(20)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .transition(.opacity)
        }
    }
}
