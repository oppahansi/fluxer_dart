# Changelog

## 0.2.0 — 2026-08-12

### Added

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

## 0.1.0

Initial scaffolding: `pubspec.yaml`, `analysis_options.yaml`, MIT
license, CI.
