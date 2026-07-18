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
                        .foregroundStyle(.white)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Profile")
                            .font(LumiTheme.Typography.headline(18))
                            .foregroundStyle(.white)
                        Text(viewModel.userEmail)
                            .font(LumiTheme.Typography.body(14))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    .glassCard()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Subscription")
                            .font(LumiTheme.Typography.headline(18))
                            .foregroundStyle(.white)
                        Text(viewModel.subscriptionTitle)
                            .font(LumiTheme.Typography.body(15).weight(.semibold))
                            .foregroundStyle(.white)
                    }
                    .glassCard()

                    Toggle("Sound", isOn: Binding(get: {
                        viewModel.soundEnabled
                    }, set: { newValue in
                        viewModel.soundEnabled = newValue
                        viewModel.applySettings()
                    }))
                    .tint(LumiTheme.Colors.crimson)
                    .glassCard()

                    Toggle("Haptics", isOn: Binding(get: {
                        viewModel.hapticsEnabled
                    }, set: { newValue in
                        viewModel.hapticsEnabled = newValue
                        viewModel.applySettings()
                    }))
                    .tint(LumiTheme.Colors.crimson)
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
