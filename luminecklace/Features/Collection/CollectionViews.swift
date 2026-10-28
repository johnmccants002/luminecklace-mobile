import SwiftUI

struct CollectionView: View {
    @ObservedObject var viewModel: CollectionViewModel
    @Namespace private var cardNamespace

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var columns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.adaptive(minimum: 150), spacing: 12)]
    }

    var body: some View {
        ZStack {
            LumiTheme.Colors.pageBackground.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Your necklaces")
                        .font(LumiTheme.Typography.display(34))
                        .foregroundStyle(LumiTheme.Colors.ink)

                    if viewModel.necklaces.isEmpty {
                        EmptyStateView(
                            title: "No Lumi linked",
                            subtitle: "There isn't a necklace connected to this account yet.",
                            systemImage: "heart.slash"
                        )

                        PrimaryButton(title: "Try Again") {
                            Task { await viewModel.retryLoad() }
                        }
                    } else {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(viewModel.necklaces) { necklace in
                                NavigationLink {
                                    NecklaceDetailView(viewModel: viewModel, necklace: necklace, namespace: cardNamespace)
                                } label: {
                                    NecklaceCardView(necklace: necklace)
                                        .matchedGeometryEffect(id: necklace.id, in: cardNamespace)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(20)
            }
        }
    }
}

struct NecklaceDetailView: View {
    @ObservedObject var viewModel: CollectionViewModel
    let necklace: NecklaceTag
    let namespace: Namespace.ID

    var body: some View {
        let necklace = viewModel.necklaces.first(where: { $0.id == self.necklace.id }) ?? self.necklace
        return ZStack {
            LumiTheme.Colors.pageBackground.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    NecklaceCardView(necklace: necklace)
                        .matchedGeometryEffect(id: necklace.id, in: namespace)

                    detailRow("Theme", value: necklace.themeKey.capitalized)
                    detailRow("Status", value: necklace.lifecycleStatus.replacingOccurrences(of: "_", with: " ").capitalized)
                    detailRow("Waiting Lumis", value: "\(necklace.availableLumiCount)")

                    PrimaryButton(title: necklace.isEquipped ? "Selected necklace" : "Select this necklace") {
                        viewModel.equip(necklace)
                    }
                    .disabled(necklace.isEquipped)

                    Spacer()
                }
                .padding(20)
            }
        }
        .navigationTitle(necklace.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func detailRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(LumiTheme.Typography.body(14).weight(.medium))
                .foregroundStyle(LumiTheme.Colors.ink.opacity(0.68))
            Spacer()
            Text(value)
                .font(LumiTheme.Typography.body(15).weight(.semibold))
                .foregroundStyle(LumiTheme.Colors.ink)
        }
        .glassCard()
    }
}
