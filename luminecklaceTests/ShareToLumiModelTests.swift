import Security
import XCTest
@testable import luminecklace

final class ShareToLumiModelTests: XCTestCase {
    func testSupportedInstagramAttachments() throws {
        for (path, kind, display) in [
            ("reel/example/", "reel", "Reel"),
            ("p/example/", "post", "Post"),
            ("stories/example/1/", "story", "Story"),
            ("example/", "profile", "Profile")
        ] {
            let attachment = makeAttachment(url: "https://www.instagram.com/\(path)", kind: kind)
            XCTAssertTrue(attachment.isSupportedInstagramLink)
            XCTAssertEqual(attachment.displayContentKind, display)
            XCTAssertNotNil(attachment.supportedDestinationURL)
        }
    }

    func testUnsafeAndUnsupportedAttachmentsAreNotActionable() {
        XCTAssertFalse(makeAttachment(url: "http://instagram.com/p/example/").isSupportedInstagramLink)
        XCTAssertFalse(makeAttachment(url: "https://instagram.com.attacker.example/p/example/").isSupportedInstagramLink)
        XCTAssertFalse(makeAttachment(url: "not a url").isSupportedInstagramLink)
        XCTAssertFalse(makeAttachment(provider: "unknown").isSupportedInstagramLink)
        XCTAssertFalse(makeAttachment(openMode: "inline").isSupportedInstagramLink)
    }

    func testSupportedWebsiteAttachmentUsesValidatedHostForDisplay() throws {
        let attachment = makeAttachment(
            url: "https://Example.com/articles/one?ref=lumi#details",
            provider: "website",
            kind: "link",
            host: "forged.example",
            ctaLabel: ""
        )

        XCTAssertTrue(attachment.isSupportedLink)
        XCTAssertTrue(attachment.isSupportedWebsiteLink)
        XCTAssertFalse(attachment.isSupportedInstagramLink)
        XCTAssertEqual(attachment.displayHost, "example.com")
        XCTAssertEqual(attachment.badgeTitle, "Website · example.com")
        XCTAssertEqual(attachment.recipientDetail, "example.com")
        XCTAssertEqual(attachment.safeCallToActionLabel, "Open website")
        XCTAssertEqual(attachment.attachmentAccessibilityLabel, "Website attachment from example.com")
        XCTAssertEqual(attachment.supportedDestinationURL?.query, "ref=lumi")
        XCTAssertEqual(attachment.supportedDestinationURL?.fragment, "details")
    }

    func testWebsiteAttachmentRejectsNonPublicDestinationsAndProviderMismatch() {
        for url in [
            "http://example.com/no",
            "https://user:pass@example.com/no",
            "https://localhost/no",
            "https://service.local/no",
            "https://10.0.0.1/no",
            "https://172.16.0.1/no",
            "https://192.168.0.1/no",
            "https://[::1]/no",
            "https://[fe80::1]/no"
        ] {
            XCTAssertFalse(
                makeAttachment(url: url, provider: "website", kind: "link").isSupportedLink,
                "Expected \(url) to be rejected"
            )
        }

        XCTAssertFalse(
            makeAttachment(
                url: "https://instagram.com/p/example/",
                provider: "website",
                kind: "link"
            ).isSupportedLink
        )
        XCTAssertFalse(
            makeAttachment(
                url: "https://example.com/article",
                provider: "instagram",
                kind: "link"
            ).isSupportedLink
        )
    }

    func testUnknownContentKindRemainsDecodable() throws {
        let attachment = makeAttachment(kind: "future-kind")
        XCTAssertTrue(attachment.isSupportedInstagramLink)
        XCTAssertEqual(attachment.displayContentKind, "Instagram link")
    }

    func testRecipientAttachmentIsTolerantAndTextOnlyStillDecodes() throws {
        var payload = readyPayload
        payload["attachment"] = attachmentPayload
        guard case let .ready(withAttachment) = try decode(payload) else {
            return XCTFail("Expected ready response")
        }
        XCTAssertTrue(withAttachment.attachment?.isSupportedInstagramLink == true)

        guard case let .ready(textOnly) = try decode(readyPayload) else {
            return XCTFail("Expected text-only response")
        }
        XCTAssertNil(textOnly.attachment)

        payload["attachment"] = ["type": 42, "provider": ["invalid"]]
        guard case let .ready(malformed) = try decode(payload) else {
            return XCTFail("Malformed attachment must not fail the Lumi")
        }
        XCTAssertNil(malformed.attachment)
    }

    func testSenderMappingsRetainQueueAndRecentlyRevealedAttachments() throws {
        let service = SenderService()
        var lumi = attachmentPayload
        lumi["id"] = "lumi-1"
        lumi["text"] = "This made me think of you."
        lumi["attachment"] = attachmentPayload
        let message = try XCTUnwrap(service.mapLumi(from: lumi, fallbackThemeKey: "heart"))
        XCTAssertTrue(message.attachment?.isSupportedInstagramLink == true)

        var necklace: [String: Any] = [
            "id": "necklace-1",
            "name": "Everyday Lumi",
            "recentlyRevealed": [[
                "id": "revealed-1",
                "text": "A remembered moment",
                "revealedAt": "2026-07-31T12:00:00Z",
                "attachment": attachmentPayload
            ]]
        ]
        necklace["queue"] = [lumi]
        let mapped = try XCTUnwrap(service.mapNecklace(from: necklace))
        XCTAssertTrue(mapped.nextLumi?.attachment?.isSupportedInstagramLink == true)
        XCTAssertTrue(mapped.recentlyRevealed.first?.attachment?.isSupportedInstagramLink == true)
    }

    func testLegacyTokenMigratesOnlyAfterVerifiedKeychainWriteAndDeleteClearsBoth() {
        let suite = "ShareToLumiModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("legacy-token", forKey: TokenStore.legacyKey)

        let keychain = FakeKeychain()
        let sharedStore = SharedAuthTokenStore(keychain: keychain, accessGroup: "test.group")
        let tokenStore = TokenStore(sharedStore: sharedStore, defaults: defaults)
        XCTAssertEqual(tokenStore.accessToken, "legacy-token")
        XCTAssertNil(defaults.string(forKey: TokenStore.legacyKey))
        XCTAssertEqual(try? sharedStore.read(), "legacy-token")

        tokenStore.accessToken = nil
        XCTAssertNil(try? sharedStore.read())
        XCTAssertNil(defaults.string(forKey: TokenStore.legacyKey))
    }

    func testFailedLegacyMigrationKeepsUserDefaultsValue() {
        let suite = "ShareToLumiModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("legacy-token", forKey: TokenStore.legacyKey)
        let keychain = FakeKeychain(addStatus: errSecNotAvailable)
        let store = SharedAuthTokenStore(keychain: keychain, accessGroup: "test.group")

        XCTAssertEqual(TokenStore(sharedStore: store, defaults: defaults).accessToken, "legacy-token")
        XCTAssertEqual(defaults.string(forKey: TokenStore.legacyKey), "legacy-token")
    }

    func testKeychainReadFailureIsNotTreatedAsSignedOut() {
        let suite = "ShareToLumiModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let keychain = FakeKeychain(copyStatus: errSecInteractionNotAllowed)
        let store = SharedAuthTokenStore(keychain: keychain, accessGroup: "test.group")
        let tokenStore = TokenStore(sharedStore: store, defaults: defaults)

        switch tokenStore.localSessionState {
        case .unavailable:
            break
        case .available, .missing:
            XCTFail("A temporary Keychain failure must remain recoverable.")
        }

        XCTAssertThrowsError(try tokenStore.requireAccessToken()) { error in
            XCTAssertTrue(error is SharedAuthTokenStoreError)
        }
    }

    private func makeAttachment(
        url: String = "https://www.instagram.com/reel/example/",
        provider: String = "instagram",
        kind: String = "reel",
        host: String = "instagram.com",
        ctaLabel: String = "View on Instagram",
        openMode: String = "external"
    ) -> LumiLinkAttachment {
        LumiLinkAttachment(
            type: "link",
            provider: provider,
            contentKind: kind,
            urlString: url,
            host: host,
            ctaLabel: ctaLabel,
            openMode: openMode
        )
    }

    private func decode(_ payload: [String: Any]) throws -> ResolveTapResponse {
        try JSONDecoder().decode(
            ResolveTapResponse.self,
            from: JSONSerialization.data(withJSONObject: payload)
        )
    }

    private var readyPayload: [String: Any] {
        [
            "status": "ready",
            "revealSessionId": "session-1",
            "necklace": ["displayName": "Lumi Necklace"],
            "lumi": ["id": "lumi-1", "text": "This made me think of you."],
            "presentation": ["theme": "heart", "animation": "breathe"]
        ]
    }

    private var attachmentPayload: [String: Any] {
        [
            "type": "link",
            "provider": "instagram",
            "contentKind": "reel",
            "url": "https://www.instagram.com/reel/example/",
            "host": "instagram.com",
            "ctaLabel": "View on Instagram",
            "openMode": "external"
        ]
    }
}

private final class FakeKeychain: KeychainOperating, @unchecked Sendable {
    private var data: Data?
    private let addStatus: OSStatus
    private let copyStatus: OSStatus?

    init(
        addStatus: OSStatus = errSecSuccess,
        copyStatus: OSStatus? = nil
    ) {
        self.addStatus = addStatus
        self.copyStatus = copyStatus
    }

    func copyMatching(_ query: CFDictionary) -> (status: OSStatus, data: Data?) {
        if let copyStatus {
            return (copyStatus, nil)
        }
        guard let data else { return (errSecItemNotFound, nil) }
        return (errSecSuccess, data)
    }

    func add(_ attributes: CFDictionary) -> OSStatus {
        guard addStatus == errSecSuccess else { return addStatus }
        let values = attributes as NSDictionary
        data = values[kSecValueData] as? Data
        return errSecSuccess
    }

    func update(_ query: CFDictionary, attributes: CFDictionary) -> OSStatus {
        let values = attributes as NSDictionary
        data = values[kSecValueData] as? Data
        return errSecSuccess
    }

    func delete(_ query: CFDictionary) -> OSStatus {
        data = nil
        return errSecSuccess
    }
}
