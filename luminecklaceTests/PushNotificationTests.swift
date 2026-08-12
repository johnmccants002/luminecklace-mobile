import Security
import UserNotifications
import XCTest
@testable import luminecklace

@MainActor
final class PushNotificationTests: XCTestCase {
    override func tearDown() {
        PushTransportURLProtocol.handler = nil
        super.tearDown()
    }

    func testAPNSTokenUsesLowercaseHexWithLeadingZeros() {
        XCTAssertEqual(
            PushNotificationManager.lowercaseHexToken(
                from: Data([0x00, 0x0A, 0x7F, 0xB0, 0xFF])
            ),
            "000a7fb0ff"
        )
    }

    func testSupportedPayloadTypesDecode() {
        let cases: [(String, PushNotificationEventType)] = [
            ("lumi.revealed", .revealed),
            ("lumi.reacted", .reacted),
            ("lumi.responded", .responded)
        ]

        for (rawValue, expected) in cases {
            let payload = PushNotificationPayload(userInfo: [
                "type": rawValue,
                "necklaceId": "necklace",
                "lumiId": "lumi"
            ])
            XCTAssertEqual(payload.type, expected)
            XCTAssertEqual(payload.safeDestination.necklaceId, "necklace")
        }
    }

    func testUnknownPayloadTypeFallsBackWithoutCrashing() {
        let payload = PushNotificationPayload(userInfo: [
            "type": "lumi.future-event",
            "necklaceId": "private-necklace"
        ])

        XCTAssertEqual(payload.type, .unknown("lumi.future-event"))
        XCTAssertNil(payload.safeDestination.necklaceId)
    }

    func testMissingNecklaceIdFallsBackSafely() {
        let payload = PushNotificationPayload(userInfo: [
            "type": "lumi.revealed",
            "lumiId": "lumi"
        ])

        XCTAssertNil(payload.safeDestination.necklaceId)
        XCTAssertEqual(payload.safeDestination.lumiId, "lumi")
    }

    func testPushDeviceRegistrationTransportContract() async throws {
        let service = makeTransportService()
        PushTransportURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/push/devices")
            XCTAssertEqual(request.httpMethod, "PUT")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer push-test-token")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

            let body = try Self.jsonBody(from: request)
            XCTAssertEqual(body["deviceToken"] as? String, "00aaff")
            XCTAssertEqual(body["environment"] as? String, "sandbox")
            XCTAssertEqual(body["bundleId"] as? String, PushAppMetadata.fullAppBundleId)
            XCTAssertEqual(body["appVersion"] as? String, "1.1")
            XCTAssertEqual(body["deviceModel"] as? String, "iPhone")
            XCTAssertEqual(body.count, 5)
            return Self.transportResponse(request, body: #"{"ok":true}"#)
        }

        try await service.register(
            PushDeviceRegistration(
                deviceToken: "00aaff",
                environment: .sandbox,
                bundleId: PushAppMetadata.fullAppBundleId,
                appVersion: "1.1",
                deviceModel: "iPhone"
            )
        )
    }

    func testPushDeviceDisableTransportContract() async throws {
        let service = makeTransportService()
        PushTransportURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/push/devices")
            XCTAssertEqual(request.httpMethod, "DELETE")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer push-test-token")

            let body = try Self.jsonBody(from: request)
            XCTAssertEqual(body["deviceToken"] as? String, "00aaff")
            XCTAssertEqual(body["environment"] as? String, "production")
            XCTAssertEqual(body["bundleId"] as? String, PushAppMetadata.fullAppBundleId)
            XCTAssertEqual(body.count, 3)
            return Self.transportResponse(request, body: #"{"ok":true}"#)
        }

        try await service.disable(
            PushDeviceDisableRequest(
                deviceToken: "00aaff",
                environment: .production,
                bundleId: PushAppMetadata.fullAppBundleId
            )
        )
    }

    func testPushPreferencesFetchTransportContract() async throws {
        let service = makeTransportService()
        PushTransportURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/push/preferences")
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer push-test-token")
            XCTAssertNil(request.httpBody)
            return Self.transportResponse(
                request,
                body: #"{"revealsEnabled":true,"reactionsEnabled":true,"responsesEnabled":true}"#
            )
        }

        let preferences = try await service.fetchPreferences()

        XCTAssertEqual(preferences, .enabledByDefault)
    }

    func testPushPreferencesPatchUsesPartialCamelCaseBodyAndReturnsFullState() async throws {
        let service = makeTransportService()
        PushTransportURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/push/preferences")
            XCTAssertEqual(request.httpMethod, "PATCH")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer push-test-token")

            let body = try Self.jsonBody(from: request)
            XCTAssertEqual(body["responsesEnabled"] as? Bool, false)
            XCTAssertNil(body["revealsEnabled"])
            XCTAssertNil(body["reactionsEnabled"])
            XCTAssertEqual(body.count, 1)
            return Self.transportResponse(
                request,
                body: #"{"revealsEnabled":true,"reactionsEnabled":true,"responsesEnabled":false}"#
            )
        }

        let preferences = try await service.updatePreferences(
            PushPreferencesUpdate(responsesEnabled: false)
        )

        XCTAssertTrue(preferences.revealsEnabled)
        XCTAssertTrue(preferences.reactionsEnabled)
        XCTAssertFalse(preferences.responsesEnabled)
    }

    func testRegistrationWaitsForAuthenticatedUser() async {
        let service = MockPushService()
        let manager = makeManager(service: service)
        await manager.start()
        manager.receiveDeviceToken(tokenData)
        await settle()

        XCTAssertTrue(service.registrations.isEmpty)
    }

    func testRegistrationStartsAfterAuthenticationWhenTokenExists() async {
        let service = MockPushService()
        let manager = makeManager(service: service)
        await manager.start()
        manager.receiveDeviceToken(tokenData)
        await settle()

        manager.updateAuthenticatedUser(id: "user-a")
        await waitUntil { service.registrations.count == 1 }

        XCTAssertEqual(service.registrations.first?.deviceToken, String(repeating: "ab", count: 32))
    }

    func testRegistrationStartsAfterTokenWhenAuthenticated() async {
        let service = MockPushService()
        let manager = makeManager(service: service)
        await manager.start()
        manager.updateAuthenticatedUser(id: "user-a")

        manager.receiveDeviceToken(tokenData)
        await waitUntil { service.registrations.count == 1 }

        XCTAssertEqual(service.registrations.first?.environment, .sandbox)
        XCTAssertEqual(service.registrations.first?.bundleId, PushAppMetadata.fullAppBundleId)
    }

    func testDuplicateRegistrationFingerprintIsNotRepeated() async {
        let service = MockPushService()
        let manager = makeManager(service: service)
        await manager.start()
        manager.updateAuthenticatedUser(id: "user-a")
        manager.receiveDeviceToken(tokenData)
        await waitUntil { service.registrations.count == 1 }

        await manager.reconcileRegistration()
        await manager.applicationDidBecomeActive()

        XCTAssertEqual(service.registrations.count, 1)
    }

    func testRegistrationRetriesAfterFailure() async {
        let service = MockPushService()
        service.registerResults = [.failure(TestError.unavailable), .success(())]
        let authorization = MockAuthorizationProvider(status: .notDetermined)
        let manager = makeManager(service: service, authorization: authorization)
        await manager.start()
        manager.updateAuthenticatedUser(id: "user-a")
        manager.receiveDeviceToken(tokenData)

        authorization.status = .authorized
        await manager.refreshPermissionState()
        await manager.reconcileRegistration()

        XCTAssertEqual(service.registrations.count, 1)
        XCTAssertNotNil(manager.lastRegistrationError)

        await manager.applicationDidBecomeActive()

        XCTAssertEqual(service.registrations.count, 2)
        XCTAssertNil(manager.lastRegistrationError)
    }

    func testDifferentUserRegistersSameInstallationAgain() async {
        let service = MockPushService()
        let manager = makeManager(service: service)
        await manager.start()
        manager.updateAuthenticatedUser(id: "user-a")
        manager.receiveDeviceToken(tokenData)
        await waitUntil { service.registrations.count == 1 }

        manager.updateAuthenticatedUser(id: "user-b")
        await waitUntil { service.registrations.count == 2 }

        XCTAssertEqual(service.registrations.count, 2)
    }

    func testAccountSwitchDuringInFlightRegistrationReconcilesNewUser() async {
        let service = MockPushService()
        service.pauseNextRegistration = true
        let manager = makeManager(service: service)
        await manager.start()
        manager.updateAuthenticatedUser(id: "user-a")
        manager.receiveDeviceToken(tokenData)
        await waitUntil { service.registrations.count == 1 }

        manager.updateAuthenticatedUser(id: "user-b")
        service.resumeRegistration()

        await waitUntil { service.registrations.count == 2 }
        XCTAssertEqual(service.registrations.count, 2)
    }

    func testSignOutWaitsForInFlightRegistrationBeforeDisablingDevice() async {
        let events = EventLog()
        let service = MockPushService(events: events)
        service.pauseNextRegistration = true
        let auth = MockAuthService(events: events)
        let manager = makeManager(service: service)
        await manager.start()
        manager.updateAuthenticatedUser(id: "user-a")
        manager.receiveDeviceToken(tokenData)
        await waitUntil { service.registrations.count == 1 }

        let state = AppState(authService: auth, pushNotificationManager: manager)
        state.user = testUser(id: "user-a")
        let signOutTask = Task { await state.signOut() }
        await settle()

        XCTAssertFalse(events.values.contains("push.disable"))
        service.resumeRegistration()
        await signOutTask.value

        XCTAssertEqual(
            events.values,
            ["push.register.start", "push.register.finish", "push.disable", "auth.signout"]
        )
        XCTAssertEqual(state.route, .auth)
    }

    func testSignOutDisablesDeviceBeforeAuthenticationAndRetainsRawToken() async {
        let events = EventLog()
        let service = MockPushService(events: events)
        let auth = MockAuthService(events: events)
        let manager = makeManager(service: service)
        manager.updateAuthenticatedUser(id: "user-a")
        manager.receiveDeviceToken(tokenData)
        let state = AppState(authService: auth, pushNotificationManager: manager)
        state.user = testUser(id: "user-a")

        await state.signOut()

        XCTAssertEqual(events.values.prefix(2), ["push.disable", "auth.signout"])
        XCTAssertEqual(manager.currentDeviceToken, String(repeating: "ab", count: 32))
        XCTAssertNil(state.user)
        XCTAssertEqual(state.route, .auth)
    }

    func testSignOutCompletesWhenDeviceDisableFails() async {
        let events = EventLog()
        let service = MockPushService(events: events)
        service.disableError = TestError.unavailable
        let auth = MockAuthService(events: events)
        let manager = makeManager(service: service)
        manager.updateAuthenticatedUser(id: "user-a")
        manager.receiveDeviceToken(tokenData)
        let state = AppState(authService: auth, pushNotificationManager: manager)
        state.user = testUser(id: "user-a")

        await state.signOut()

        XCTAssertTrue(events.values.contains("auth.signout"))
        XCTAssertFalse(auth.hasAccessToken)
        XCTAssertEqual(state.route, .auth)
    }

    func testPendingNavigationSurvivesUnauthenticatedColdStart() async {
        let auth = MockAuthService()
        auth.hasAccessToken = false
        let manager = makeManager()
        let navigation = MockNavigationService(necklaces: [necklace("owned", equipped: true)])
        let state = AppState(
            authService: auth,
            pushNotificationManager: manager,
            notificationNavigationService: navigation
        )
        manager.notificationResponseHandler = nil
        manager.handleNotificationResponse(userInfo: pushUserInfo(necklaceId: "owned"))

        await state.consumePendingNotificationDestinationIfPossible()
        XCTAssertNotNil(manager.pendingDestination)
        XCTAssertEqual(state.route, .auth)

        auth.hasAccessToken = true
        state.user = testUser(id: "user-a")
        manager.updateAuthenticatedUser(id: "user-a")
        await state.consumePendingNotificationDestinationIfPossible()

        XCTAssertNil(manager.pendingDestination)
        XCTAssertEqual(state.equippedNecklace?.id, "owned")
        XCTAssertEqual(state.route, .senderHome)
    }

    func testNotificationSelectsOwnedNecklace() async {
        let auth = MockAuthService()
        let manager = makeManager()
        let navigation = MockNavigationService(necklaces: [
            necklace("first", equipped: true),
            necklace("target", equipped: false)
        ])
        let state = AppState(
            authService: auth,
            pushNotificationManager: manager,
            notificationNavigationService: navigation
        )
        state.user = testUser(id: "user-a")
        manager.notificationResponseHandler = nil
        manager.handleNotificationResponse(userInfo: pushUserInfo(necklaceId: "target"))

        await state.consumePendingNotificationDestinationIfPossible()

        XCTAssertEqual(state.equippedNecklace?.id, "target")
        XCTAssertNotNil(state.notificationHomeFocusId)
    }

    func testUnauthorizedNecklaceFallsBackToOwnedSelection() async {
        let auth = MockAuthService()
        let manager = makeManager()
        let navigation = MockNavigationService(necklaces: [necklace("owned", equipped: true)])
        let state = AppState(
            authService: auth,
            pushNotificationManager: manager,
            notificationNavigationService: navigation
        )
        state.user = testUser(id: "user-a")
        manager.notificationResponseHandler = nil
        manager.handleNotificationResponse(userInfo: pushUserInfo(necklaceId: "not-owned"))

        await state.consumePendingNotificationDestinationIfPossible()

        XCTAssertEqual(state.equippedNecklace?.id, "owned")
        XCTAssertEqual(state.route, .senderHome)
    }

    func testForegroundEventRefreshesWithoutForcedNavigation() async {
        let auth = MockAuthService()
        let manager = makeManager()
        var refreshed = necklace("owned", equipped: true)
        refreshed.recentlyRevealed = [revealedLumi("fresh")]
        let navigation = MockNavigationService(necklaces: [refreshed])
        let state = AppState(
            authService: auth,
            pushNotificationManager: manager,
            notificationNavigationService: navigation
        )
        state.user = testUser(id: "user-a")
        state.route = .senderHome
        state.ownedNecklaces = [necklace("owned", equipped: true)]

        manager.handleForegroundNotification(userInfo: pushUserInfo(necklaceId: "owned"))
        await waitUntil { state.equippedNecklace?.recentlyRevealed.first?.id == "fresh" }

        XCTAssertEqual(state.route, .senderHome)
        XCTAssertEqual(navigation.callCount, 1)
    }

    func testForegroundEventDoesNotInterruptRecipientReveal() async {
        let auth = MockAuthService()
        let manager = makeManager()
        let navigation = MockNavigationService(necklaces: [necklace("owned", equipped: true)])
        let state = AppState(
            authService: auth,
            pushNotificationManager: manager,
            notificationNavigationService: navigation
        )
        state.user = testUser(id: "user-a")
        state.route = .recipientReveal

        let shouldPresent = manager.handleForegroundNotification(
            userInfo: pushUserInfo(necklaceId: "owned")
        )
        await settle()

        XCTAssertFalse(shouldPresent)
        XCTAssertEqual(navigation.callCount, 0)
        XCTAssertEqual(state.route, .recipientReveal)
    }

    func testPreferenceFailureRollsBackOptimisticChange() async {
        let service = MockPushService()
        service.preferences = .enabledByDefault
        service.updateError = TestError.unavailable
        let manager = makeManager()
        await manager.start()
        let state = AppState(pushNotificationManager: manager)
        state.user = testUser(id: "user-a")
        let viewModel = SettingsViewModel(appState: state, pushService: service)
        await viewModel.loadNotifications()

        await viewModel.setPreference(.reveals, enabled: false)

        XCTAssertEqual(viewModel.pushPreferences?.revealsEnabled, true)
        XCTAssertNotNil(viewModel.notificationError)
    }

    func testDeniedPermissionExposesOpenSettingsState() async {
        let authorization = MockAuthorizationProvider(status: .denied)
        let opener = MockSettingsOpener()
        let manager = makeManager(authorization: authorization, opener: opener)
        await manager.start()
        let state = AppState(pushNotificationManager: manager)
        let viewModel = SettingsViewModel(appState: state, pushService: MockPushService())

        await viewModel.loadNotifications()
        viewModel.enableNotifications()

        XCTAssertEqual(viewModel.permissionState, .denied)
        XCTAssertEqual(opener.openCount, 1)
    }

    func testContextualPromptIsSuppressedDuringRecipientExperienceAndAfterDismissal() async {
        let defaults = makeDefaults()
        let manager = makeManager(
            authorization: MockAuthorizationProvider(status: .notDetermined),
            defaults: defaults
        )
        await manager.start()
        manager.updateAuthenticatedUser(id: "user-a")

        await manager.considerContextualPrompt(isRecipientExperienceActive: true)
        XCTAssertFalse(manager.isEducationPresented)

        await manager.considerContextualPrompt(isRecipientExperienceActive: false)
        XCTAssertTrue(manager.isEducationPresented)
        manager.dismissEducation()
        await manager.considerContextualPrompt(isRecipientExperienceActive: false)
        XCTAssertFalse(manager.isEducationPresented)
    }

    private let tokenData = Data(repeating: 0xAB, count: 32)

    private func makeTransportService() -> PushDeviceService {
        let suite = "PushTransportTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defaults.set("push-test-token", forKey: TokenStore.legacyKey)

        let tokenStore = TokenStore(
            sharedStore: SharedAuthTokenStore(
                keychain: PushTestKeychain(),
                accessGroup: "push.tests"
            ),
            defaults: defaults
        )
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PushTransportURLProtocol.self]
        let client = APIClient(
            baseURL: URL(string: "https://push.example.test")!,
            session: URLSession(configuration: configuration),
            tokenStore: tokenStore
        )
        return PushDeviceService(client: client)
    }

    private static func jsonBody(from request: URLRequest) throws -> [String: Any] {
        let data: Data
        if let body = request.httpBody {
            data = body
        } else {
            let stream = try XCTUnwrap(request.httpBodyStream)
            stream.open()
            defer { stream.close() }

            var streamed = Data()
            var buffer = [UInt8](repeating: 0, count: 1_024)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count < 0 { throw try XCTUnwrap(stream.streamError) }
                if count == 0 { break }
                streamed.append(buffer, count: count)
            }
            data = streamed
        }
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private static func transportResponse(
        _ request: URLRequest,
        status: Int = 200,
        body: String
    ) -> (HTTPURLResponse, Data) {
        (
            HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!,
            Data(body.utf8)
        )
    }

    private func makeManager(
        service: MockPushService? = nil,
        authorization: MockAuthorizationProvider? = nil,
        opener: MockSettingsOpener? = nil,
        defaults: UserDefaults? = nil
    ) -> PushNotificationManager {
        PushNotificationManager(
            deviceService: service ?? MockPushService(),
            authorizationProvider: authorization ?? MockAuthorizationProvider(status: .authorized),
            remoteRegistrar: MockRemoteRegistrar(),
            settingsOpener: opener ?? MockSettingsOpener(),
            environmentProvider: MockEnvironmentProvider(environment: .sandbox),
            metadata: PushAppMetadata(
                bundleId: PushAppMetadata.fullAppBundleId,
                appVersion: "1.1",
                deviceModel: "iPhone"
            ),
            defaults: defaults ?? makeDefaults(),
            now: { Date(timeIntervalSince1970: 1_000) }
        )
    }

    private func makeDefaults() -> UserDefaults {
        let suite = "PushNotificationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func waitUntil(
        _ predicate: @escaping @MainActor () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<100 {
            if predicate() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for asynchronous state", file: file, line: line)
    }

    private func settle() async {
        try? await Task.sleep(for: .milliseconds(40))
    }

    private func pushUserInfo(necklaceId: String) -> [AnyHashable: Any] {
        [
            "type": "lumi.revealed",
            "necklaceId": necklaceId,
            "lumiId": "lumi"
        ]
    }

    private func testUser(id: String) -> User {
        User(
            id: id,
            email: "sender@example.com",
            displayName: "Sender",
            subscriptionTier: .free
        )
    }

    private func necklace(_ id: String, equipped: Bool) -> NecklaceTag {
        NecklaceTag(
            id: id,
            name: id,
            sku: "LUMI-TEST",
            themeKey: "heart",
            isEquipped: equipped,
            rarity: nil,
            includedPackage: "Love"
        )
    }

    private func revealedLumi(_ id: String) -> RevealedLumi {
        RevealedLumi(
            id: id,
            text: "Fresh",
            revealedAt: Date(),
            experience: Experience(
                themeKey: "heart",
                animationKey: "breathe",
                soundKey: "soft"
            )
        )
    }
}

private final class PushTransportURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private final class PushTestKeychain: KeychainOperating, @unchecked Sendable {
    func copyMatching(_ query: CFDictionary) -> (status: OSStatus, data: Data?) {
        (errSecItemNotFound, nil)
    }

    func add(_ attributes: CFDictionary) -> OSStatus { errSecInteractionNotAllowed }
    func update(_ query: CFDictionary, attributes: CFDictionary) -> OSStatus {
        errSecInteractionNotAllowed
    }
    func delete(_ query: CFDictionary) -> OSStatus { errSecItemNotFound }
}

@MainActor
private final class MockPushService: PushDeviceServicing {
    var registrations: [PushDeviceRegistration] = []
    var disables: [PushDeviceDisableRequest] = []
    var registerResults: [Result<Void, Error>] = []
    var disableError: Error?
    var updateError: Error?
    var preferences = PushPreferences.enabledByDefault
    var pauseNextRegistration = false
    private var registrationContinuation: CheckedContinuation<Void, Never>?
    private let events: EventLog?

    init(events: EventLog? = nil) {
        self.events = events
    }

    func register(_ registration: PushDeviceRegistration) async throws {
        registrations.append(registration)
        events?.values.append("push.register.start")
        if pauseNextRegistration {
            pauseNextRegistration = false
            await withCheckedContinuation { continuation in
                registrationContinuation = continuation
            }
        }
        events?.values.append("push.register.finish")
        if !registerResults.isEmpty {
            try registerResults.removeFirst().get()
        }
    }

    func resumeRegistration() {
        registrationContinuation?.resume()
        registrationContinuation = nil
    }

    func disable(_ request: PushDeviceDisableRequest) async throws {
        events?.values.append("push.disable")
        disables.append(request)
        if let disableError { throw disableError }
    }

    func fetchPreferences() async throws -> PushPreferences {
        preferences
    }

    func updatePreferences(_ update: PushPreferencesUpdate) async throws -> PushPreferences {
        if let updateError { throw updateError }
        if let value = update.revealsEnabled { preferences.revealsEnabled = value }
        if let value = update.reactionsEnabled { preferences.reactionsEnabled = value }
        if let value = update.responsesEnabled { preferences.responsesEnabled = value }
        return preferences
    }
}

@MainActor
private final class MockAuthorizationProvider: NotificationAuthorizationProviding {
    var status: UNAuthorizationStatus

    init(status: UNAuthorizationStatus) {
        self.status = status
    }

    func authorizationStatus() async -> UNAuthorizationStatus { status }

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        status = .authorized
        return true
    }

    func clearBadge() async {}
}

@MainActor
private final class MockRemoteRegistrar: RemoteNotificationRegistering {
    private(set) var registerCount = 0
    func registerForRemoteNotifications() { registerCount += 1 }
}

@MainActor
private final class MockSettingsOpener: ApplicationSettingsOpening {
    private(set) var openCount = 0
    func openNotificationSettings() { openCount += 1 }
}

private struct MockEnvironmentProvider: APNSEnvironmentProviding {
    let environment: APNSEnvironment
    func currentEnvironment() -> APNSEnvironment { environment }
}

@MainActor
private final class MockAuthService: AuthenticationServicing {
    var hasAccessToken = true
    var signOutError: Error?
    private let events: EventLog?

    init(events: EventLog? = nil) {
        self.events = events
    }

    func signIn(email: String, password: String) async throws -> AuthResult {
        AuthResult(
            user: User(
                id: "user-a",
                email: email,
                displayName: nil,
                subscriptionTier: .free
            )
        )
    }

    func resetPassword(email: String) async throws {}

    func me() async throws -> User {
        User(
            id: "user-a",
            email: "sender@example.com",
            displayName: nil,
            subscriptionTier: .free
        )
    }

    func signOut() async throws {
        events?.values.append("auth.signout")
        if let signOutError { throw signOutError }
        hasAccessToken = false
    }

    func clearLocalSession() {
        events?.values.append("auth.clear")
        hasAccessToken = false
    }
}

@MainActor
private final class MockNavigationService: NotificationNavigationServicing {
    var necklaces: [NecklaceTag]
    private(set) var callCount = 0

    init(necklaces: [NecklaceTag]) {
        self.necklaces = necklaces
    }

    func listSenderNecklaces() async throws -> [NecklaceTag] {
        callCount += 1
        return necklaces
    }
}

@MainActor
private final class EventLog {
    var values: [String] = []
}

private enum TestError: Error {
    case unavailable
}
