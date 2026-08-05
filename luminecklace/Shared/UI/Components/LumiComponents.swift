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
                .foregroundStyle(LumiTheme.Colors.ink.opacity(0.92))

            Group {
                if secure {
                    SecureField(label, text: $text)
                } else {
                    TextField(label, text: $text)
                        .textInputAutocapitalization(autocapitalization)
                }
            }
            .keyboardType(keyboardType)
            .foregroundStyle(LumiTheme.Colors.ink)
            .padding(14)
            .background(Color.white.opacity(0.92))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(LumiTheme.Colors.cardStroke, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: Color.black.opacity(0.03), radius: 8, y: 4)
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
                .foregroundStyle(LumiTheme.Colors.rose)

            Text(message?.text ?? "Tap your necklace to reveal a message.")
                .font(LumiTheme.Typography.headline(28))
                .foregroundStyle(LumiTheme.Colors.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
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
                    .foregroundStyle(LumiTheme.Colors.rose)
                Spacer()
                if necklace.isEquipped {
                    Text("Equipped")
                        .font(LumiTheme.Typography.body(11).weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(LumiTheme.Colors.roseSoft)
                        .clipShape(Capsule())
                        .foregroundStyle(LumiTheme.Colors.rose)
                }
            }
            Text(necklace.name)
                .font(LumiTheme.Typography.body(15).weight(.semibold))
                .foregroundStyle(LumiTheme.Colors.ink)
            Text(necklace.themeKey.capitalized + " Theme")
                .font(LumiTheme.Typography.body(12))
                .foregroundStyle(LumiTheme.Colors.ink.opacity(0.68))
            if let rarity = necklace.rarity {
                Text(rarity)
                    .font(LumiTheme.Typography.body(11).weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(LumiTheme.Colors.roseSoft)
                    .foregroundStyle(LumiTheme.Colors.rose)
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
                        .foregroundStyle(LumiTheme.Colors.ink)
                    if package.isPremium {
                        Image(systemName: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(LumiTheme.Colors.rose)
                    }
                }
                Text(package.isPremium ? "Premium package" : "Included")
                    .font(LumiTheme.Typography.body(12))
                    .foregroundStyle(LumiTheme.Colors.ink.opacity(0.68))
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
                    .foregroundStyle(LumiTheme.Colors.rose)
            Text(title)
                .font(LumiTheme.Typography.headline(20))
                .foregroundStyle(LumiTheme.Colors.ink)
            Text(subtitle)
                .font(LumiTheme.Typography.body(14))
                .foregroundStyle(LumiTheme.Colors.ink.opacity(0.68))
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

struct LumiAttachmentBadge: View {
    let attachment: LumiLinkAttachment?

    var body: some View {
        if let attachment, attachment.isSupportedInstagramLink {
            Label(
                "Instagram · \(attachment.displayContentKind)",
                systemImage: "arrow.up.right.square"
            )
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(LumiTheme.Colors.ink.opacity(0.62))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(LumiTheme.Colors.roseSoft.opacity(0.62), in: Capsule())
            .accessibilityLabel("Instagram \(attachment.displayContentKind) attachment")
        }
    }
}
