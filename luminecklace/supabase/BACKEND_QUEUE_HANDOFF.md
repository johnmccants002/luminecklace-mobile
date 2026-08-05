# Backend implementation prompt: Current, Up Next, and Reserve

Implement the server side of Lumi's ordered necklace queue. Treat each necklace
as exactly one sequence:

`current -> up_next[] -> reserve[]`

Both editable sections are unbounded. A message ID may occur only once. Current
is immutable through sender queue APIs.

## Required sender contract

Include this object on every sender necklace response and every successful
create/mutation response:

```json
{
  "queue": {
    "revision": 12,
    "current": { "id": "...", "text": "...", "presentation": {} },
    "upNext": [],
    "reserve": []
  }
}
```

Preserve stored array order exactly. Reject malformed/duplicate membership
instead of silently repairing it.

Update both creation routes to require
`destination: "up_next" | "reserve"`:

- `POST /api/sender/necklaces/{id}/lumis`
- `POST /api/sender/necklaces/{id}/lumis/from-library`

The library request is `{ "messageId": "...", "destination": "..." }`; remove
the personalized `text` override.

Add:

`POST /api/sender/necklaces/{id}/queue/mutations`

```json
{
  "expectedRevision": 12,
  "idempotencyKey": "uuid",
  "operation": {
    "type": "reorder | move | remove",
    "messageId": "when required",
    "section": "up_next | reserve",
    "destination": "up_next | reserve",
    "placement": "first | last",
    "orderedMessageIds": []
  }
}
```

Execute each operation in one transaction after locking the necklace. Validate
sender ownership, current immutability, exact reorder membership, uniqueness,
and message state. Increment `revision` exactly once and return the full
snapshot. Deduplicate retries by `(necklace_id, idempotency_key)`. For a stale
revision, return HTTP 409 with the latest full snapshot.

## Reveal behavior

`POST /api/tap/resolve` must return a stable current message/reveal session and
must not consume or advance the queue.

`POST /api/tap/revealed` must idempotently:

1. Mark the resolved current message revealed/archived.
2. Promote the first Up Next message to current.
3. If Up Next is empty, promote the first Reserve message directly to current.
4. Otherwise leave current empty.
5. Compact only the source section, preserve all relative order, and increment
   the queue revision once.

Reserve never refills Up Next. Fetching, editing, adding, app launch, or merely
having an empty Up Next section must never promote or activate Reserve.

## Migration and tests

Use `20260727_split_up_next_reserve.sql` as the schema/RPC foundation. Migrate
the first existing published queued message to current and the remainder to Up
Next in their existing order. Do not materialize or automatically feed the
legacy Reserve approval/catalog pool into editable Reserve.

Add integration tests for destination-aware creation, every mutation,
concurrent revision conflicts, duplicate prevention, cross-section ordering,
stable repeated resolve, repeated reveal confirmation, direct Reserve
promotion only after confirmed consumption, and no activation during reads or
sender edits.
