import SwiftUI

struct SoundManager {
    func play(soundKey: String, enabled: Bool) {
        guard enabled else { return }
        print("[SoundManager] would play sound: \(soundKey)")
    }
}

struct HapticsManager {
    func impact(enabled: Bool) {
        guard enabled else { return }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }
}
