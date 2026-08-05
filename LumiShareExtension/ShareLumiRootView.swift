import SwiftUI

struct ShareLumiRootView: View {
    @ObservedObject var viewModel: ShareLumiViewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            Group {
                switch viewModel.state {
                case .extracting:
                    progress("Reading Instagram link…")
                case .loadingNecklaces:
                    progress("Finding your necklaces…")
                case .ready, .submitting:
                    compose
                case .success:
                    success
                case .authenticationRequired:
                    status(
                        icon: "person.crop.circle.badge.exclamationmark",
                        title: "Sign in to Lumi",
                        message: "Open the Lumi app and sign in before sharing.",
                        retry: false
                    )
                case .noEligibleNecklaces:
                    status(
                        icon: "heart.slash",
                        title: "No active necklace",
                        message: "Set up or activate a necklace in Lumi before sharing.",
                        retry: true
                    )
                case .unsupportedShare:
                    status(
                        icon: "link.badge.plus",
                        title: "Instagram link not found",
                        message: "This Instagram link couldn’t be read.",
                        retry: true
                    )
                case let .failure(message):
                    status(
                        icon: "wifi.exclamationmark",
                        title: "Couldn’t add this Lumi",
                        message: message,
                        retry: true
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .preferredColorScheme(.light)
        .onDisappear {
            viewModel.cancelTasks()
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Share to Lumi")
                    .font(.system(size: 22, weight: .semibold, design: .serif))
                Text("Turn this into a message they’ll discover.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Close", action: viewModel.cancel)
                .font(.subheadline.weight(.semibold))
                .accessibilityHint("Closes Share to Lumi without adding a message")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var compose: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                instagramPreview
                messageEditor
                destinationControls

                Button(action: viewModel.submit) {
                    HStack(spacing: 10) {
                        if viewModel.state == .submitting {
                            ProgressView().tint(.white)
                        }
                        Text(viewModel.state == .submitting ? "Adding…" : "Add to Lumi")
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color(red: 0.78, green: 0.18, blue: 0.31), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.canSubmit || viewModel.state == .submitting)
                .opacity(viewModel.canSubmit || viewModel.state == .submitting ? 1 : 0.55)
            }
            .padding(20)
        }
    }

    private var instagramPreview: some View {
        HStack(spacing: 14) {
            Image(systemName: "play.rectangle.on.rectangle")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(Color(red: 0.78, green: 0.18, blue: 0.31))
                .frame(width: 48, height: 48)
                .background(Color(red: 0.98, green: 0.90, blue: 0.92), in: RoundedRectangle(cornerRadius: 13))

            VStack(alignment: .leading, spacing: 3) {
                Text("Instagram").font(.headline)
                Text(viewModel.extractedLink?.displayContentKind ?? "Instagram link")
                    .font(.subheadline).foregroundStyle(.secondary)
                Text("instagram.com").font(.caption).foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.black.opacity(0.07)))
        .accessibilityElement(children: .combine)
    }

    private var messageEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Message").font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(viewModel.message.count)/500")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            TextEditor(text: $viewModel.message)
                .font(.body)
                .frame(minHeight: 92, maxHeight: 120)
                .padding(8)
                .scrollContentBackground(.hidden)
                .background(.background, in: RoundedRectangle(cornerRadius: 15))
                .overlay(RoundedRectangle(cornerRadius: 15).stroke(.black.opacity(0.08)))
                .accessibilityLabel("Lumi message")
        }
    }

    private var destinationControls: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Send to").font(.subheadline.weight(.semibold))
                Spacer()
                if viewModel.necklaces.count == 1 {
                    Text(viewModel.selectedNecklace?.name ?? "Lumi Necklace")
                        .font(.subheadline).foregroundStyle(.secondary)
                } else {
                    Picker("Send to", selection: $viewModel.selectedNecklaceID) {
                        ForEach(viewModel.necklaces) { necklace in
                            Text(necklace.name).tag(Optional(necklace.id))
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
            }

            Divider()

            HStack {
                Text("Place in").font(.subheadline.weight(.semibold))
                Spacer()
                Picker("Place in", selection: $viewModel.destination) {
                    ForEach(ShareQueueDestination.allCases) { destination in
                        Text(destination.title).tag(destination)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
        }
        .padding(15)
        .background(.background, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.black.opacity(0.07)))
    }

    private var success: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 58, weight: .light))
                .foregroundStyle(Color(red: 0.22, green: 0.60, blue: 0.38))
            Text("Added to \(viewModel.selectedNecklace?.name ?? "Lumi")")
                .font(.title3.weight(.semibold))
            Text("They’ll discover it the next time this Lumi reaches the front.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .transition(.opacity)
    }

    private func progress(_ title: String) -> some View {
        VStack(spacing: 14) {
            ProgressView().controlSize(.large)
            Text(title).font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(30)
    }

    private func status(icon: String, title: String, message: String, retry: Bool) -> some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Color(red: 0.78, green: 0.18, blue: 0.31))
            Text(title).font(.title3.weight(.semibold))
            Text(message)
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if retry {
                Button("Try Again", action: viewModel.tryAgain)
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.78, green: 0.18, blue: 0.31))
            }
            Button("Close", action: viewModel.cancel)
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: 360)
        .padding(28)
    }
}
