# Changelog

## 0.3.0

- No new surface of its own. Re-released to pin `fluxer_dart_core`,
  `fluxer_dart_rest` and `fluxer_dart_gateway` 0.3.0, which add
  announcement channels and crossposting and fix two decoding crashes.
- Note that `Message.type` is now a `MessageType?` with the wire value on
  `Message.rawType`, and `Message.flags` is a `MessageFlags`.

## 0.2.0

- `Bot` gained the `attachments` manager and eleven event streams:
  `onChannelPinsUpdate`, `onMessageDeleteBulk`,
  `onMessageReactionRemoveAll`, `onMessageReactionRemoveEmoji`,
  `onGuildEmojisUpdate`, `onGuildStickersUpdate`,
  `onGuildAuditLogEntryCreate`, `onWebhooksUpdate`, `onInviteCreate`,
  `onInviteDelete` and `onSessionsReplace`.
- `Bot.updatePresence` and `Bot.requestGuildMembers` send the two new
  gateway commands. `requestGuildMembers` picks the shard that owns the
  guild.
- `Bot.fetchUser` resolves a user from cache, falling back to REST.
  `Bot.user` remains the synchronous cache-only lookup.
- `Bot` takes `ignoredEvents`, `initialPresence` and `sessionFlags`,
  passed through to every shard's IDENTIFY.

## 0.1.0 — Initial release

- `Bot` — the facade tying `fluxer_dart_gateway`, `fluxer_dart_rest`,
  `fluxer_dart_core`, and `fluxer_dart_utils` together: typed per-event
  streams (`onReady`, `onMessageCreate`, `onGuildCreate`, and 19 more),
  every REST resource manager, cache-aside lookups (`guild()`,
  `channel()`, `member()`) backed by pluggable `CacheProvider`s,
  `reply()`, and `login()`.
- `Bot.selfId` — this bot's own user id, populated once `READY` comes
  through.
- `CommandRouter` — message-content command routing: fluent
  `.command(name, handler)` registration, Chain-of-Responsibility
  middleware (including the built-in `cooldown()`), and
  `commandNames` to introspect what's registered.
- `requireGuildPermission(PermissionFlag)` — a `CommandMiddleware`
  resolving a member's effective guild permissions fresh on every call.
