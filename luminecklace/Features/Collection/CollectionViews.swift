import SwiftUI

struct CollectionView: View {
    @ObservedObject var viewModel: CollectionViewModel
    @Namespace private var cardNamespace

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        ZStack {
            LumiTheme.Colors.pageBackground.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Collection")
                        .font(LumiTheme.Typography.display(34))
                        .foregroundStyle(LumiTheme.Colors.ink)

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
        ZStack {
            LumiTheme.Colors.pageBackground.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {
                NecklaceCardView(necklace: necklace)
                    .matchedGeometryEffect(id: necklace.id, in: namespace)

                detailRow("SKU", value: necklace.sku)
                detailRow("Theme", value: necklace.themeKey.capitalized)
                detailRow("Status", value: necklace.lifecycleStatus.replacingOccurrences(of: "_", with: " ").capitalized)
                detailRow("Waiting Lumis", value: "\(necklace.availableLumiCount)")
                detailRow("Animation Preview", value: "Fade + soft shimmer")

                PrimaryButton(title: necklace.isEquipped ? "Currently Equipped" : "Set as Equipped") {
                    viewModel.equip(necklace)
                }

                Spacer()
            }
            .padding(20)
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
