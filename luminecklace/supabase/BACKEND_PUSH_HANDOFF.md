# Push notifications v1: backend contract and operations

The backend implementation lives in
[`johnmccants002/luminecklace`](https://github.com/johnmccants002/luminecklace).
This document records the contract consumed by the iOS app and the operational
behavior delivered on `main` in commit
[`13e2d034`](https://github.com/johnmccants002/luminecklace/commit/13e2d034581acb85eeaadc4e772be628de0f8d67)
through [PR #12](https://github.com/johnmccants002/luminecklace/pull/12).

The authenticated full app is the only push client. The App Clip and Share
Extension remain unauthenticated recipients and must never register for or
receive push notifications. Keep APNs credentials in the backend deployment
secret manager; do not add keys, team IDs, key IDs, bearer credentials, or raw
session identifiers to this repository.

## Persisted model

The migration is
`supabase/migrations/20260805120000_ios_push_notifications.sql` in the backend
repository. It creates private, service-role-only push tables and transactional
RPCs:

- `push_devices` stores the authenticated owner, lower-case hexadecimal token,
  `ios` platform, bundle ID, APNs environment, optional app version and device
  model, active state, and created, updated, and last-seen timestamps. An
  installation is unique by `(bundle_id, apns_environment, device_token)`.
- `push_preferences` stores `reveals_enabled`, `reactions_enabled`, and
  `responses_enabled`, all defaulting to `true`.
- `push_events` is the durable, deduplicated event outbox. It retains the
  internal reveal-session reference needed for server-side idempotency, but that
  reference is never copied into an APNs payload.
- `push_deliveries` records per-device work with `pending`, `processing`,
  `retry`, `sent`, `invalid_token`, or `failed` status plus claim, attempt, APNs,
  and timing metadata.

Registration is an upsert. Registering an existing installation under a new
authenticated account reassigns it, reactivates it, refreshes metadata, and
marks queued work for the previous owner as failed with `DEVICE_REASSIGNED`.
Deactivation is idempotent and similarly prevents queued work from being sent.

Preference defaults are virtual on the first read: `GET` returns all three
fields as `true` without requiring a database row. `PATCH` upserts the stored
row, changes only supplied keys, and returns the full preference object.

## Authenticated HTTP contract

All four routes require the existing bearer token and return `401` before
reading or mutating another user's data. Request bodies are strictly validated.

### Register or refresh a device

`PUT /api/push/devices`

```json
{
  "deviceToken": "lowercase-hex-token",
  "environment": "sandbox",
  "bundleId": "luminecklace.luminecklace",
  "appVersion": "1.1",
  "deviceModel": "iPhone"
}
```

`environment` must be `sandbox` or `production`; the token must be nonempty
lower-case hexadecimal; and the bundle ID must be the full-app bundle ID. A
successful upsert returns:

```json
{ "ok": true }
```

### Disable a device

`DELETE /api/push/devices`

```json
{
  "deviceToken": "lowercase-hex-token",
  "environment": "sandbox",
  "bundleId": "luminecklace.luminecklace"
}
```

The backend accepts an omitted `bundleId` by defaulting it to the configured app
bundle, but the iOS client sends it explicitly. An absent or already inactive
installation is a successful no-op and returns `{ "ok": true }`.

### Read preferences

`GET /api/push/preferences`

Returns the complete camel-case object:

```json
{
  "revealsEnabled": true,
  "reactionsEnabled": true,
  "responsesEnabled": true
}
```

### Update preferences

`PATCH /api/push/preferences`

Accepts at least one known boolean field, rejects unknown or non-boolean fields,
and returns the complete updated object. For example:

```json
{ "responsesEnabled": false }
```

## Event production and idempotency

The recipient state mutation and durable `push_events` insertion occur in the
same database transaction:

1. `lumi.revealed` is produced after a reveal is successfully confirmed.
2. `lumi.reacted` is produced only when the reaction transitions from absent to
   its first accepted value. Later reaction changes update data without sending
   another notification.
3. `lumi.responded` is produced for the one accepted written response.

Event uniqueness is based on the reveal session, using these internal keys:

```text
reveal:<reveal-session-id>
reaction:<reveal-session-id>
response:<reveal-session-id>
```

The sender is resolved through `necklace_ownerships.sender_user_id`. The
matching preference is applied when the event is enqueued, and one delivery is
created for every device active at that time. If the preference is disabled,
the deduplicated event is still recorded but no delivery row is created. There
is no `suppressed` delivery status. Devices registered later do not receive old
events, and repeated mutations or dispatcher retries cannot create duplicate
logical events or duplicate per-device deliveries.

## APNs payload and privacy contract

The production alert copy is intentionally generic:

| Event | Title | Body |
| --- | --- | --- |
| `lumi.revealed` | `Your Lumi was opened` | `Someone just revealed your message.` |
| `lumi.reacted` | `They reacted to your Lumi` | `They reacted to your Lumi.` |
| `lumi.responded` | `You received a response` | `Open Lumi to see their response.` |

The outgoing application payload contains only the event type and navigation
identifiers outside `aps`:

```json
{
  "aps": {
    "alert": {
      "title": "Your Lumi was opened",
      "body": "Someone just revealed your message."
    },
    "sound": "default",
    "thread-id": "necklace:necklace-uuid"
  },
  "type": "lumi.revealed",
  "necklaceId": "necklace-uuid",
  "lumiId": "lumi-uuid"
}
```

There is no badge or category field. Never include Lumi text, written-response
text, necklace names, reaction values, recipient data, reveal-session IDs,
access tokens, credentials, or raw session identifiers in APNs payloads or
logs. Internal outbox metadata is not part of the outgoing payload.
`necklaceId` and `lumiId` are navigation identifiers only; the app re-authorizes
ownership and fetches current sender data after opening.

## Delivery behavior

APNs requests use the device's stored environment:

- `sandbox` uses `https://api.sandbox.push.apple.com`.
- `production` uses `https://api.push.apple.com`.
- The request path is `/3/device/<token>`.
- `apns-topic` is the configured bundle ID.
- `apns-push-type` is `alert`, priority is `10`, and `apns-id` is the delivery
  ID.

Provider JWTs are cached for 50 minutes and requests time out after 10 seconds.
An immediate dispatch attempt runs after the request transaction with a batch
size of 10. The authenticated `/api/cron/push` recovery route runs every five
minutes with a batch size of 50; dispatcher calls are capped at 100 deliveries.
Workers claim rows with `SKIP LOCKED`, and processing claims older than five
minutes are eligible for recovery.

Transport errors, timeouts, APNs `429`, and APNs `5xx` responses retry up to
eight total attempts. `Retry-After` is honored; otherwise retry delay starts at
30 seconds, doubles to a one-hour cap, and adds up to 15 seconds of jitter.
Configuration failures are terminal.

APNs `410` or the reasons `BadDeviceToken`, `DeviceTokenNotForTopic`,
`ExpiredToken`, and `Unregistered` mark the installation inactive, mark its
remaining queued deliveries `invalid_token`, and stop retrying. A token is
never moved between APNs environments or retried against the other host.

## Deployment and verification

The backend requires these deployment secrets and settings:

- `APNS_TEAM_ID`
- `APNS_KEY_ID`
- `APNS_PRIVATE_KEY` or `APNS_PRIVATE_KEY_BASE64`
- `APNS_BUNDLE_ID=luminecklace.luminecklace`
- `APNS_DEFAULT_ENVIRONMENT`
- `CRON_SECRET`

Apply the push migration before deploying code that calls its RPCs. Apple Push
Notifications must be enabled for the explicit `luminecklace.luminecklace` App
ID, with regenerated development, Ad Hoc, and App Store provisioning profiles.

PR #12 reports the focused backend suite passing 12 of 12 tests, with lint and
production build also passing. The suite covers authenticated routes, strict
request shapes, installation reassignment and idempotent deletion, virtual
preference defaults and partial updates, transactional event deduplication,
payload privacy, environment routing, APNs headers, `Retry-After`, retries, and
invalid-token cleanup.

Physical-device verification remains required: use a development-signed iPhone
against sandbox APNs for all three event types, then repeat with TestFlight
against production APNs. Also confirm preference opt-outs, account switching,
sign-out deactivation, lock-screen privacy, and safe notification navigation.
