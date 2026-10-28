import SwiftUI

struct ShareToLumiHelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 36))
                    .foregroundStyle(LumiTheme.Colors.rose)
                    .accessibilityHidden(true)
                Text("Something made you think of them?")
                    .font(LumiTheme.Typography.headline(28))
                Text("Send a website or Instagram link with a personal message. They can open the link after their Lumi is revealed.")
                    .font(.body)
                step("1. Find a link", "Open a public HTTPS website in Safari, or a post or Reel in Instagram. Open that app’s Share menu; in Instagram, choose the system sharing option if needed.")
                step("2. Choose Lumi", "Find Lumi in the row of apps. If it isn’t visible, scroll to More, then Edit to enable or favorite Lumi.")
                step("3. Make it personal", "Write your message, confirm the necklace, and add it to Up Next. You can choose Reserve if you want it to play after Up Next runs out.")
                Text("Sign in to Lumi first and make sure your necklace is linked. Wait for the confirmation before leaving the share screen.")
                    .font(.subheadline)
                    .foregroundStyle(LumiTheme.Colors.ink.opacity(0.75))
            }
            .padding(24)
        }
        .foregroundStyle(LumiTheme.Colors.ink)
        .background(LumiTheme.Colors.pageBackground)
        .navigationTitle("Share a link to Lumi")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func step(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            Text(detail).font(.body).fixedSize(horizontal: false, vertical: true)
        }
    }
}
