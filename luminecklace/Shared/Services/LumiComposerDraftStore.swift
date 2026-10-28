import Foundation

struct LumiComposerDraft: Codable, Equatable {
    var text: String
    var background: LumiBackgroundKey
    var font: LumiFontKey
    var textSize: LumiTextSizeKey
    var textAlignment: LumiTextAlignmentKey
    var textPosition: LumiTextPositionKey
    var destination: QueueSection
}

struct LumiComposerDraftContext: Equatable {
    let userID: String
    let necklaceID: String

    var storageKey: String {
        let user = Data(userID.utf8).base64EncodedString()
        let necklace = Data(necklaceID.utf8).base64EncodedString()
        return "lumi.composer-draft.v1.\(user).\(necklace)"
    }
}

struct LumiComposerDraftStore {
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load(for context: LumiComposerDraftContext) -> LumiComposerDraft? {
        guard let data = defaults.data(forKey: context.storageKey) else { return nil }
        return try? JSONDecoder().decode(LumiComposerDraft.self, from: data)
    }

    func save(_ draft: LumiComposerDraft, for context: LumiComposerDraftContext) {
        guard !draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            remove(for: context)
            return
        }
        guard let data = try? JSONEncoder().encode(draft) else { return }
        defaults.set(data, forKey: context.storageKey)
    }

    func remove(for context: LumiComposerDraftContext) {
        defaults.removeObject(forKey: context.storageKey)
    }
}
