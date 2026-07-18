import SwiftUI

struct PackagesView: View {
    @ObservedObject var viewModel: PackagesViewModel

    var body: some View {
        ZStack {
            LumiTheme.Colors.pageBackground.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Packages")
                        .font(LumiTheme.Typography.display(34))
                        .foregroundStyle(.white)

                    if viewModel.subscription == .free {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Unlock Premium Packages")
                                .font(LumiTheme.Typography.headline(18))
                                .foregroundStyle(.white)
                            Text("Upgrade to Premium for exclusive message drops and seasonal experiences.")
                                .font(LumiTheme.Typography.body(14))
                                .foregroundStyle(.white.opacity(0.78))
                            Button("Upgrade (Mock)") {}
                                .buttonStyle(SecondaryButtonStyle())
                        }
                        .glassCard()
                    }

                    ForEach(viewModel.packages) { package in
                        PackageRowView(
                            package: package,
                            canEnable: !package.isPremium || viewModel.subscription == .premium,
                            onToggle: { isOn in
                                viewModel.toggle(package, isOn: isOn)
                            }
                        )
                    }
                }
                .padding(20)
            }
        }
    }
}
