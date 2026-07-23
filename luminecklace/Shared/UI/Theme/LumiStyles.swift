import SwiftUI

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(LumiTheme.Typography.body(17).weight(.semibold))
            .foregroundStyle(.white)
            .padding(.vertical, 15)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(
                    colors: [LumiTheme.Colors.rose, LumiTheme.Colors.gold],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .opacity(configuration.isPressed ? 0.85 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: LumiTheme.Colors.rose.opacity(0.18), radius: 10, y: 6)
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(LumiTheme.Typography.body(16).weight(.semibold))
            .foregroundStyle(LumiTheme.Colors.rose)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(Color.white.opacity(configuration.isPressed ? 0.88 : 0.96))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(LumiTheme.Colors.cardStroke, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct GlassCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(
                LinearGradient(
                    colors: [LumiTheme.Colors.glassTop, LumiTheme.Colors.glassBottom],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(LumiTheme.Colors.cardStroke, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: Color(red: 0.90, green: 0.80, blue: 0.79).opacity(0.18), radius: 12, y: 6)
    }
}

extension View {
    func glassCard() -> some View {
        modifier(GlassCardModifier())
    }
}
