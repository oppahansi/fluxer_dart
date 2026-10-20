# Changelog

## 0.5.0

- `Bot.queryMembers`: Request Guild Members as a single call. It
  collects every chunk of its own answer, matched by nonce, and throws
  `FluxerGatewayRateLimitException` when the full-list budget is spent.
  Input the server would drop without answering (more than 100 user
  ids, a limit over 100) throws instead of timing out.
- `onChannelUpdateBulk`, `onGuildRoleUpdateBulk`, `onGuildMembersChunk`,
  `onRateLimited` and `onUserUpdate`.
- Cache: a channel bulk update replaces the cached channels, member
  chunks populate the member and user caches, and `USER_UPDATE` the user
  cache.
- Fixed: deleting a channel now also evicts the cached threads under
  it. The server sends no `THREAD_DELETE` for them, so they previously
  stayed cached.
- `GUILD_CREATE` and `GUILD_SYNC` now seed the channel, member and user
  caches, so `Bot.channel` no longer fetches what the gateway already
  sent.
- `Bot.subscribe` (Lazy Request), `guildCounts`, `channelMemberCounts`
  and `forumUnreads`; the first two match their answer by nonce.
- `Bot.presence(guildId, userId)` and `Bot.voiceStates(guildId)`, backed
  by new injectable `presenceCache` and `voiceStateCache`. Presences come
  from subscriptions, member lists and member chunks; voice states from
  `GUILD_CREATE` and `VOICE_STATE_UPDATE`.
- `onGuildSync`, `onPresenceUpdate`, `onPresenceUpdateBulk`,
  `onGuildMemberListUpdate`, `onThreadMemberListUpdate`,
  `onGuildCountsUpdate`, `onChannelMemberCountsUpdate`, `onForumUnreads`
  and `onVoiceStateUpdate`.
- `Bot.discovery` and `Bot.webhookTokens`, the token-authenticated
  webhook client pointed at the same instance as `Bot.rest`.
- `onChannelRecipientAdd` and `onChannelRecipientRemove`; either evicts
  the cached group DM so its recipients are re-fetched.
- `onMessageReactionAddMany`.

## 0.4.0

- `Bot.threads`, a `ThreadRestManager`.
- `onThreadCreate`, `onThreadUpdate`, `onThreadDelete`,
  `onThreadListSync`, `onThreadMemberUpdate` and `onThreadMembersUpdate`.
- Threads are cached as channels. `Bot.channel(threadId)` returns a
  `ThreadChannel`, kept current by the thread events and seeded from each
  guild's active threads at connect. Thread events carry the whole
  thread, so an update replaces the cached entry rather than evicting it.
- Deleting a thread's parent channel sends no `THREAD_DELETE` for the
  threads in it, so those entries stay cached until re-fetched.
- Pins `fluxer_dart_core`, `fluxer_dart_rest` and `fluxer_dart_gateway`
  0.4.0.

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
