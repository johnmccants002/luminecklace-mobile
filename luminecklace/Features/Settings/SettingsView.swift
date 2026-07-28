import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        ZStack {
            LumiTheme.Colors.pageBackground.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Settings")
                        .font(LumiTheme.Typography.display(34))
                        .foregroundStyle(LumiTheme.Colors.ink)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Profile")
                            .font(LumiTheme.Typography.headline(18))
                            .foregroundStyle(LumiTheme.Colors.ink)
                        Text(viewModel.userEmail)
                            .font(LumiTheme.Typography.body(14))
                            .foregroundStyle(LumiTheme.Colors.ink.opacity(0.72))
                    }
                    .glassCard()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Subscription")
                            .font(LumiTheme.Typography.headline(18))
                            .foregroundStyle(LumiTheme.Colors.ink)
                        Text(viewModel.subscriptionTitle)
                            .font(LumiTheme.Typography.body(15).weight(.semibold))
                            .foregroundStyle(LumiTheme.Colors.rose)
                    }
                    .glassCard()

                    Toggle("Sound", isOn: Binding(get: {
                        viewModel.soundEnabled
                    }, set: { newValue in
                        viewModel.soundEnabled = newValue
                        viewModel.applySettings()
                    }))
                    .tint(LumiTheme.Colors.rose)
                    .glassCard()

                    Toggle("Haptics", isOn: Binding(get: {
                        viewModel.hapticsEnabled
                    }, set: { newValue in
                        viewModel.hapticsEnabled = newValue
                        viewModel.applySettings()
                    }))
                    .tint(LumiTheme.Colors.rose)
                    .glassCard()

                    Button("Sign Out") {
                        viewModel.signOut()
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
                .padding(20)
            }
        }
    }
}
