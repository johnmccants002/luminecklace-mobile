import Foundation

private struct StoredClipRedemption: Codable {
    let necklaceID: String?
    let necklaceName: String
    let basePackageIDs: [String]
    let redeemedAt: Date
}

final class ClipRedemptionStore {
    private let defaults: UserDefaults
    private let key = "lumi_clip_redeemed_activation"

    init(defaults: UserDefaults? = UserDefaults(suiteName: ClipHandoffConfig.appGroupID)) {
        self.defaults = defaults ?? .standard
    }

    func load() -> ClipActivationResult? {
        guard let data = defaults.data(forKey: key) else {
            return nil
        }

        guard let stored = try? JSONDecoder().decode(StoredClipRedemption.self, from: data) else {
            defaults.removeObject(forKey: key)
            return nil
        }

        return ClipActivationResult(
            necklaceID: stored.necklaceID,
            necklaceName: stored.necklaceName,
            basePackageIDs: stored.basePackageIDs
        )
    }

    func save(_ result: ClipActivationResult) {
        let stored = StoredClipRedemption(
            necklaceID: result.necklaceID,
            necklaceName: result.necklaceName,
            basePackageIDs: result.basePackageIDs,
            redeemedAt: Date()
        )

        guard let data = try? JSONEncoder().encode(stored) else {
            return
        }

        defaults.set(data, forKey: key)
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }
}
