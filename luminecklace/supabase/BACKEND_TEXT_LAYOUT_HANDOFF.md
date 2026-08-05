# Backend handoff: Lumi text presentation

Implement persistence and API support for the curated text presentation used by
the iOS app and App Clip. This is a fixed-value presentation contract, not a
freeform coordinate system.

## Supported values and defaults

| Field | Supported values | Default |
| --- | --- | --- |
| `background` | `heart`, `champagne`, `rose`, `midnight` | `heart` |
| `font` | `serif`, `rounded` | `serif` |
| `textSize` | `small`, `medium`, `large` | `medium` |
| `textAlignment` | `leading`, `center`, `trailing` | `center` |
| `textPosition` | `top`, `center`, `bottom` | `center` |

Do not add arbitrary coordinates, numeric font sizes, rotation, scale, line
height, or per-word formatting.

## Sender write contract

Accept the same presentation object on both routes:

- `POST /api/sender/necklaces/{necklaceId}/lumis`
- `PATCH /api/sender/necklaces/{necklaceId}/lumis/{messageId}`

Create example:

```json
{
  "text": "You are loved.",
  "destination": "up_next",
  "presentation": {
    "background": "midnight",
    "font": "rounded",
    "textSize": "large",
    "textAlignment": "center",
    "textPosition": "bottom"
  }
}
```

Edit example:

```json
{
  "text": "You are deeply loved.",
  "presentation": {
    "background": "rose",
    "font": "serif",
    "textSize": "medium",
    "textAlignment": "leading",
    "textPosition": "top"
  }
}
```

The presentation input allowlist must contain exactly:

```text
background
font
textSize
textAlignment
textPosition
```

Do not require or accept `animation` and `sound` from this sender composer.
Those legacy values may remain internally defaulted and may remain in responses
for older clients, but they are not part of this write contract.

Validate each supplied value against the table above. Return HTTP 400 with a
field-specific error for an unsupported key or value. Do not silently persist
unknown future values.

For backward compatibility:

- Create requests without `presentation` receive all defaults.
- Missing fields in a create presentation receive their individual defaults.
- A text-only PATCH preserves the message's stored presentation.
- If a PATCH includes presentation fields, update only supplied fields.

## Persistence

The existing `messages.theme_key` can remain the canonical storage for
`background`. Add strongly constrained columns for the other values:

```sql
alter table public.messages
    add column if not exists font_key text not null default 'serif',
    add column if not exists text_size_key text not null default 'medium',
    add column if not exists text_alignment_key text not null default 'center',
    add column if not exists text_position_key text not null default 'center';
```

Add check constraints:

```sql
font_key in ('serif', 'rounded')
text_size_key in ('small', 'medium', 'large')
text_alignment_key in ('leading', 'center', 'trailing')
text_position_key in ('top', 'center', 'bottom')
```

Also constrain `theme_key` to the supported backgrounds if existing production
data permits it. Otherwise, normalize legacy/unknown backgrounds to `heart`
when serializing the API response and migrate them separately.

Library/Explore enqueue must copy the template's presentation values into the
new message row. It must store a snapshot rather than resolving the template's
current presentation every time the recipient opens it.

## Response contract

Return the complete presentation on every serialized Lumi:

```json
{
  "id": "message-id",
  "text": "You are loved.",
  "presentation": {
    "background": "midnight",
    "font": "rounded",
    "textSize": "large",
    "textAlignment": "center",
    "textPosition": "bottom"
  }
}
```

Apply this serializer consistently to:

- Create responses
- Edit responses
- Sender necklace queue responses
- Current, Up Next, and Reserve queue snapshots
- Recently revealed responses
- Explore/library responses and enqueue responses
- Recipient `POST /api/tap/resolve` responses

The successful create/edit response must contain the server-persisted Lumi, not
an echo of the request. When the queue endpoint returns a snapshot, use the same
serializer for `current`, every `upNext` item, and every `reserve` item.

Update `sender_queue_snapshot` from
`20260727_split_up_next_reserve.sql`; it currently emits only legacy
`theme`/`animation`/`sound` values.

For a transition period, responses may include both `theme` and `background`,
with both derived from `messages.theme_key`. New clients use `background`.

## Suggested validation shape

```ts
const presentationKeys = new Set([
  "background",
  "font",
  "textSize",
  "textAlignment",
  "textPosition",
]);

const defaults = {
  background: "heart",
  font: "serif",
  textSize: "medium",
  textAlignment: "center",
  textPosition: "center",
};
```

Reject `Object.keys(presentation)` entries outside the allowlist. Then validate
each value against its enum. Keep this validation shared between POST, PATCH,
and library enqueue rather than maintaining route-specific copies.

## Required backend tests

1. Create persists and returns all five presentation values.
2. PATCH updates text and all five presentation values.
3. Text-only PATCH preserves existing presentation.
4. Create without presentation applies all defaults.
5. Partial legacy presentation applies defaults for missing create fields.
6. Every unknown key returns HTTP 400.
7. Every unknown enum value returns HTTP 400 with the field name.
8. Queue snapshots preserve presentation for current, Up Next, and Reserve.
9. Recently revealed responses preserve presentation.
10. Library enqueue copies the returned template presentation.
11. Recipient tap resolve returns the same presentation stored by the sender.
12. Repeated resolve returns an identical presentation snapshot.
13. Old rows created before the migration serialize with safe defaults.
14. Sender ownership and PATCH authorization remain enforced.

## Rollout checklist

1. Apply and backfill the database columns.
2. Deploy the shared validator and serializer.
3. Deploy POST, PATCH, queue, library, history, and tap-response updates.
4. Run the backend integration tests against staging.
5. Verify a staging create request with all five fields returns HTTP 2xx.
6. Verify the returned queue snapshot matches the stored values.
7. Open the same Lumi through the App Clip and compare its rendering inputs.
8. Deploy the backend before releasing a mobile build that sends these fields.
