# Sender-First Supabase Contract

This app refactor expects these backend interfaces:

- `claim_pending_orders_for_user` (RPC/function)
  - Called after sender OTP login.
  - Links pending orders to the authenticated sender by normalized email.
  - Idempotent.

- `list_sender_necklaces_with_current_message` (app endpoint or RPC wrapper)
  - Returns sender-owned necklaces and `hasPublishedMessage`.
  - Used to route into selection/setup/home.

- `publish` sender message endpoint
  - Persists and publishes the sender's first message.

- `resolve_tap_message` (Edge Function or RPC wrapper)
  - Public-safe tap resolver using signed/opaque `tap_token`.
  - Returns `message_ready` or `fallback_ready` payload for App Clip reveal.

The migration in `supabase/migrations/20260415_sender_first_schema.sql` includes
table scaffolding, RLS, and base SQL functions for the sender-first flow.

## Backend handoffs

- `BACKEND_QUEUE_HANDOFF.md` defines Current, Up Next, Reserve, and reveal
  advancement behavior.
- `BACKEND_TEXT_LAYOUT_HANDOFF.md` defines the curated composer presentation
  input, persistence, validation, and response contract.
