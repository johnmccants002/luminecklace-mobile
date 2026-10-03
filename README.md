# Luminecklace iOS

This Xcode project contains the full Luminecklace app, the recipient App Clip, and the Share to Lumi extension.

## Share to Lumi

Share to Lumi lets a signed-in sender share a public HTTPS website or Instagram link into a necklace queue without downloading the destination content. From Safari, Instagram, or another app, choose **Share**, select **Lumi**, confirm the necklace and message, choose **Up Next** or **Reserve**, and tap **Add to Lumi**. The extension submits the link while it is open and closes only after the backend confirms success.

The recipient still sees the Lumi message first. After the shared word-reveal presentation reaches its completed phase, the App Clip or full app fades in a dedicated link action. Instagram uses **View on Instagram**; other websites use **Open website** and display the validated hostname. The app opens only the normalized HTTPS URL after an explicit tap and never opens links automatically.

### Targets and identifiers

| Target | Bundle identifier | Purpose |
| --- | --- | --- |
| `luminecklace` | `luminecklace.luminecklace` | Full sender and recipient app |
| `lumiclip` | `luminecklace.luminecklace.Clip` | Unauthenticated recipient App Clip |
| `LumiShareExtension` | `luminecklace.luminecklace.ShareExtension` | Website and Instagram share-sheet compose experience |

`LumiShareExtension` is embedded in the full app's **Embed App Extensions** phase. It is not embedded in `lumiclip`. The shared `LumiShareExtension` scheme builds the extension and its focused test target.

### Supported share inputs

The production activation rule accepts one `public.url` item or plain text. The extractor prefers URL providers, then plain-text providers, then an extension item's attributed content. It accepts public HTTPS destinations up to 4,096 bytes with no embedded credentials. Local/reserved hostnames and non-public IP ranges are rejected. Exact `instagram.com` and `www.instagram.com` hosts retain Reel, post, Story, and profile classification; every other accepted host is a generic website and displays its normalized ASCII hostname.

The extension deliberately does not download media, scrape HTML, call destination APIs, resolve DNS, follow redirects, retain the source item, or create thumbnails. Those operations would increase privacy exposure, memory use, and extension latency without helping the recipient flow.

The final `NSExtensionActivationRule` is:

```xml
<dict>
    <key>NSExtensionActivationSupportsWebURLWithMaxCount</key>
    <integer>1</integer>
    <key>NSExtensionActivationSupportsText</key>
    <true/>
</dict>
```

There is no `TRUEPREDICATE` activation rule.

### Shared authentication

The full app and Share Extension use a generic-password Keychain item with:

- Access group: `$(AppIdentifierPrefix)luminecklace.shared`
- Service: `com.luminecklace.sender-auth`
- Account: `supabase-access-token`
- Accessibility: `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
- iCloud synchronization: disabled

The App Clip does not have the Keychain Sharing entitlement and remains an unauthenticated recipient experience.

On the full app's first token read, `TokenStore` checks the shared Keychain. When it is empty, it migrates `UserDefaults.standard["lumi_access_token"]`, reads the Keychain item back to verify the write, and only then removes the legacy value. Sign-in writes the Keychain directly. Sign-out deletes both shared credentials and any remaining legacy value. The Share Extension never reads the containing app's private defaults.

### Backend request

The extension calls:

```text
GET /api/sender/necklaces
POST /api/sender/necklaces/<necklaceId>/lumis/from-share
```

The creation body is:

```json
{
  "clientRequestId": "<session UUID>",
  "url": "https://example.com/article?ref=lumi",
  "text": "This made me think of you.",
  "destination": "up_next"
}
```

The backend must apply the same public-HTTPS validation before persisting the URL. Generic website responses keep the existing attachment shape:

```json
{
  "type": "link",
  "provider": "website",
  "contentKind": "link",
  "url": "https://example.com/article?ref=lumi",
  "host": "example.com",
  "ctaLabel": "Open website",
  "openMode": "external"
}
```

Instagram responses retain `provider: "instagram"` and their existing content kinds and CTA. Deploy this backend support before releasing the generalized Share Extension; no endpoint or storage-shape migration is required.

Blank text is omitted so the backend may apply its default. The response decoder requires only the created `lumi` and `idempotentReplay`; unknown fields and the queue snapshot are ignored. Both `200` idempotent replay and `201` creation are successful. A `409` is shown as a safe nontechnical failure and never causes a new request ID.

`clientRequestId` is created once in `ShareLumiViewModel.init`. It is retained for the entire compose session, including retry after transient errors, and simultaneous submits are rejected while a request is active.

### Running and testing

List schemes and installed simulators:

```bash
xcodebuild -list -project luminecklace.xcodeproj
xcrun simctl list devices available
```

Build each product:

```bash
xcodebuild -project luminecklace.xcodeproj -scheme luminecklace -sdk iphonesimulator -configuration Debug build
xcodebuild -project luminecklace.xcodeproj -scheme lumiclip -sdk iphonesimulator -configuration Debug build
xcodebuild -project luminecklace.xcodeproj -scheme LumiShareExtension -sdk iphonesimulator -configuration Debug build
```

Run tests with an installed simulator destination rather than hardcoding a model that may not exist:

```bash
xcodebuild -project luminecklace.xcodeproj -scheme luminecklace -destination 'platform=iOS Simulator,id=<device-id>' test
xcodebuild -project luminecklace.xcodeproj -scheme lumiclip -destination 'platform=iOS Simulator,id=<device-id>' test
xcodebuild -project luminecklace.xcodeproj -scheme LumiShareExtension -destination 'platform=iOS Simulator,id=<device-id>' test
```

For device verification, install and sign in to the full app first. Share both a Safari page and an Instagram post or Reel through **Share → Lumi**, edit the compose fields, and submit. Repeat for both queue destinations, multiple necklaces, no-authentication, inactive-necklace, and retry cases. Confirm website rows show the normalized hostname and Instagram rows retain their content kind. Then invoke the necklace in both the App Clip and full app and verify the correct action appears only after the last word.

The extension intentionally provides a Close action instead of forcing the containing app open. Share Extensions cannot safely use `UIApplication.shared`, responder-chain URL-opening workarounds, or private APIs for that behavior.

### Apple Developer portal and signing

Before a device or distribution build:

1. Register the Share Extension App ID `luminecklace.luminecklace.ShareExtension`.
2. Enable **Keychain Sharing** for the full app App ID and Share Extension App ID.
3. Add the same `luminecklace.shared` Keychain group to both App IDs.
4. Regenerate development, Ad Hoc, and App Store provisioning profiles for both changed App IDs.
5. Verify the extension profile is selected for `LumiShareExtension` and the refreshed full-app profile is selected for `luminecklace`.
6. Leave the App Clip's capabilities and profile unchanged; it must not gain sender authentication access.

The repository's build settings use the team-prefix-expanded Keychain group. The Swift token store reads the expanded value from each product's Info.plist; the checked-in development-team fallback is only for test or command-line contexts where generated metadata is unavailable.

## Privacy and compatibility

Attachment data is optional throughout sender queues, recently revealed history, full-app recipient resolution, and App Clip resolution. Missing, malformed, unknown-provider, and future content-kind attachments never prevent the Lumi text from decoding. Only validated external Instagram or public website HTTPS attachments produce actions, and clients derive display hostnames from the validated URL rather than trusting attachment metadata.

Sender networking redacts authentication bodies, all Lumi-write bodies, and all Lumi-write response bodies. The Share Extension does not log access tokens, URLs, message text, or raw private response content.

## iOS push notifications

Push notifications are implemented only in the signed-in full application (`luminecklace.luminecklace`). The recipient App Clip remains unauthenticated and never asks for notification permission. The Share Extension does not register with APNs or receive notification capabilities.

The app explains the benefit after a sender reaches the home experience and calls Apple’s authorization prompt only after the sender chooses **Turn On Notifications**. A **Not Now** choice is retained locally and is not shown on every launch. Settings always shows the authoritative iOS permission state and provides account controls for reveals, reactions, and written responses. Notification payloads contain identifiers and lock-screen-safe copy only; full Lumi and written-response text are fetched after the app opens.

### Capability and provisioning

1. In Apple Developer Certificates, Identifiers & Profiles, open the explicit App ID for `luminecklace.luminecklace` and enable **Push Notifications**.
2. Create or update the APNs key used by the backend and restrict its operational access according to the deployment environment. Do not place the `.p8` key in this repository or the app bundle.
3. Regenerate development, Ad Hoc, and App Store provisioning profiles for the full-app App ID after enabling Push Notifications.
4. In Xcode, confirm the `luminecklace` target shows the Push Notifications capability and retains Associated Domains and Keychain Sharing.
5. Leave the `lumiclip` and `LumiShareExtension` App IDs, entitlements, and profiles unchanged.

The checked-in full-app entitlement uses `$(APS_ENVIRONMENT)`. Debug sets it to `development`; Release sets it to `production`. The same build value is expanded into the generated Info.plist, where the client maps `development` to `sandbox` and `production` to `production`. Because both the signed entitlement and runtime value come from one configuration setting, they cannot drift without an explicit build-setting override. This avoids relying on `#if DEBUG` and keeps TestFlight/App Store tokens in the production APNs environment. Tests inject an environment provider rather than depending on signing metadata.

### Backend contracts

All routes require the existing bearer token:

```text
PUT    /api/push/devices
DELETE /api/push/devices
GET    /api/push/preferences
PATCH  /api/push/preferences
```

Registration sends the lower-case hexadecimal device token, APNs environment, `luminecklace.luminecklace`, app version, and general device model. Disable sends `deviceToken`, `environment`, and `bundleId` in its JSON body. The app never logs the token, bearer credential, or private notification payload identifiers.

The app does not maintain an unread-count model or send client-generated badge counts. It conservatively clears any existing badge after a notification opens sender home.

### Physical-device verification

Simulator push behavior does not replace device verification. On a development-signed iPhone:

1. Sign in, reach sender home, confirm the Lumi explanation appears, and choose **Turn On Notifications**.
2. Confirm Apple’s permission sheet appears only after that choice and the backend stores a `sandbox` token.
3. Reveal a Lumi through the App Clip, react, and submit a written response; confirm each produces owner-safe notification copy.
4. Tap each notification and confirm the app refreshes data, selects the owned necklace, and shows recently revealed activity. An unknown necklace must fall back safely.
5. Receive a push while the app is foregrounded; confirm banner and sound presentation, refreshed sender data, and no forced navigation. While an in-app recipient reveal is active, confirm the banner is suppressed so the reveal is not interrupted.
6. Deny permission and confirm Settings shows **Disabled in iOS Settings** with an **Open iOS Settings** action.
7. Toggle each account preference and confirm the backend persists it and failed writes visibly roll back.
8. Sign out and confirm device deactivation occurs before the local bearer token is removed. Sign in as another account and confirm the installation is upserted to that user.
9. Install a TestFlight build and confirm registration uses `production` and production APNs delivery succeeds.

`BadDeviceToken` most commonly means the backend sent a sandbox token to production APNs (or the reverse), used a token for a different topic/bundle ID, or used credentials that do not authorize `luminecklace.luminecklace`. Also verify the current provisioning profile contains `aps-environment`, the APNs key/team/key IDs match the backend configuration, and the app has supplied a fresh token after reinstall or signing changes.
