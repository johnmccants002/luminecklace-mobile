import SwiftUI

struct LumiExperienceView: View {
    let experience: ExploreLumi
    let isActive: Bool

    var body: some View {
        LumiExperienceRenderer(content: experience.content, isActive: isActive)
    }
}
