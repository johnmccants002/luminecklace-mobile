import SwiftUI

struct FavoritesView: View {
    @ObservedObject var viewModel: FavoritesViewModel

    var body: some View {
        ZStack {
            LumiTheme.Colors.pageBackground.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 12) {
                Text("Favorites")
                    .font(LumiTheme.Typography.display(34))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                Picker("Filter", selection: $viewModel.selectedPackageId) {
                    ForEach(viewModel.packageFilters, id: \.self) { filter in
                        Text(filter.capitalized).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)

                if viewModel.filteredFavorites.isEmpty {
                    EmptyStateView(
                        title: "No favorites yet",
                        subtitle: "Save messages from Home to build your favorites list.",
                        systemImage: "heart.slash"
                    )
                    .padding(20)
                } else {
                    List {
                        ForEach(viewModel.filteredFavorites) { message in
                            MessageCardView(message: message)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .swipeActions {
                                    Button(role: .destructive) {
                                        viewModel.remove(message)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
        }
    }
}
