import SwiftUI

final class SoundManager {
    func play(soundKey: String, enabled: Bool) {
        guard enabled else { return }
        print("[SoundManager] would play sound: \(soundKey)")
    }
}

final class HapticsManager {
    func impact(enabled: Bool) {
        guard enabled else { return }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }
}
