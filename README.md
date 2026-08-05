# Luminecklace iOS

This Xcode project contains the full Luminecklace app, the recipient App Clip, and the Share to Lumi extension.

## Share to Lumi

Share to Lumi lets a signed-in sender share an Instagram HTTPS link into a necklace queue without downloading the Instagram post. From Instagram, choose **Share**, select **Lumi**, confirm the necklace and message, choose **Up Next** or **Reserve**, and tap **Add to Lumi**. The extension submits the link while it is open and closes only after the backend confirms success.

The recipient still sees the Lumi message first. After the shared word-reveal presentation reaches its completed phase, the App Clip or full app fades in a dedicated **View on Instagram** action. That action opens the normalized HTTPS URL supplied by the backend. iOS may route the universal link to Instagram when installed; otherwise it opens the browser. The app never creates an `instagram://` URL and never opens Instagram automatically.

### Targets and identifiers

| Target | Bundle identifier | Purpose |
| --- | --- | --- |
| `luminecklace` | `luminecklace.luminecklace` | Full sender and recipient app |
| `lumiclip` | `luminecklace.luminecklace.Clip` | Unauthenticated recipient App Clip |
| `LumiShareExtension` | `luminecklace.luminecklace.ShareExtension` | Instagram share-sheet compose experience |

`LumiShareExtension` is embedded in the full app's **Embed App Extensions** phase. It is not embedded in `lumiclip`. The shared `LumiShareExtension` scheme builds the extension and its focused test target.

### Supported share inputs

The production activation rule accepts one `public.url` item or plain text. The extractor prefers URL providers, then plain-text providers, then an extension item's attributed content. It accepts HTTPS URLs whose exact host is `instagram.com` or `www.instagram.com` and recognizes Reel, post, Story, and profile paths. Look-alike hosts and HTTP URLs are rejected.

The extension deliberately does not download media, scrape HTML, call Instagram APIs, follow redirects, retain the source item, or create thumbnails. Those operations would increase privacy exposure, memory use, and extension latency without helping the recipient flow.

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
  "url": "https://www.instagram.com/reel/example/",
  "text": "This made me think of you.",
  "destination": "up_next"
}
```

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

For device verification, install and sign in to the full app first, open an Instagram post or Reel, choose **Share → Lumi**, edit the compose fields, and submit. Repeat for both queue destinations, multiple necklaces, no-authentication, inactive-necklace, and retry cases. Confirm the resulting queue row has an Instagram badge. Then invoke the necklace in both the App Clip and full app and verify the Instagram action appears only after the last word.

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

Attachment data is optional throughout sender queues, recently revealed history, full-app recipient resolution, and App Clip resolution. Missing, malformed, unknown-provider, and future content-kind attachments never prevent the Lumi text from decoding. Only a validated external Instagram HTTPS attachment produces an action.

Sender networking redacts authentication bodies, all Lumi-write bodies, and all Lumi-write response bodies. The Share Extension does not log access tokens, URLs, message text, or raw private response content.
