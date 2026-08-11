# fluxer.dart

A bot framework for [Fluxer](https://fluxer.app), written in Dart.

```dart
import 'package:fluxer/fluxer.dart';

Future<void> main() async {
  final bot = Bot(token: 'your-bot-token');

  bot.onMessageCreate.listen((event) async {
    final message = event.message;
    if (message.author.bot) return;
    if (message.content == '!ping') {
      await bot.reply(message, MessageBuilder(content: 'pong'));
    }
  });

  await bot.login();
}
```

## Why this exists

Fluxer's own docs are still mostly unwritten placeholders, so this
framework — and the whole `fluxer_*` package family it's built on — was
built by reading Fluxer's actual open-source client (`fluxerapp/fluxer`,
AGPL-3.0) directly: its OpenAPI spec for the REST surface, and
`GatewayConstants.ts`/`GatewaySocket.ts`/`EventRouter.ts` for the gateway
wire protocol. See [`fluxer_core`](https://github.com/oppahansi/fluxer_core)
and [`fluxer_gateway`](https://github.com/oppahansi/fluxer_gateway)'s
READMEs for exactly what was verified where.

## Design

`Bot` is a **facade** over the ecosystem's other packages — it owns a
`GatewayShardManager` ([`fluxer_gateway`](https://github.com/oppahansi/fluxer_gateway))
and a `RestClient` ([`fluxer_rest`](https://github.com/oppahansi/fluxer_rest)),
and exposes:

- Typed per-event streams (`onReady`, `onMessageCreate`, `onGuildCreate`, ...)
  built on top of `fluxer_gateway`'s single `Stream<GatewayEvent>`, so bot
  authors don't need to `switch` on the sealed event hierarchy themselves
  unless they want to.
- Resource managers (`guilds`, `channels`, `messages`, `members`, `bans`,
  `emojis`, `stickers`, `roles`, `invites`, `webhooks`) straight from
  `fluxer_rest`.
- Cache-aside convenience methods — `guild(id)`, `channel(id)`,
  `member(guildId, userId)` return a cached value when one exists,
  otherwise fetch via REST and cache the result; `user(id)` is cache-only
  (there's no bare `GET /users/{id}` endpoint to fall back to). The caches
  themselves are pluggable `CacheProvider`s
  ([`fluxer_utils`](https://github.com/oppahansi/fluxer_utils)), populated
  automatically as dispatch events arrive — a default in-memory
  implementation is used unless a host app supplies its own.
- `reply(message, builder)` — sends to the channel a message was posted in.
- `login()` — fetches the gateway URL and recommended shard count via
  `GET /gateway/bot` (never hardcoded — see
  [`GatewayBotInfo`](https://github.com/oppahansi/fluxer_core)'s doc
  comment for why) and connects one `GatewayConnection` per shard.

## What's here

Login, sharding, reconnect/resume, typed event streams for 22 dispatch
events, the full REST resource-manager surface, and cache-aside resource
lookups. A message-content command router hasn't landed yet — see the
roadmap in this ecosystem's planning docs.

## Part of the fluxer.dart ecosystem

| Package | Purpose |
|---|---|
| [`fluxer_utils`](https://github.com/oppahansi/fluxer_utils) | generic building blocks |
| [`fluxer_core`](https://github.com/oppahansi/fluxer_core) | domain models |
| [`fluxer_rest`](https://github.com/oppahansi/fluxer_rest) | REST client |
| [`fluxer_gateway`](https://github.com/oppahansi/fluxer_gateway) | WebSocket gateway client |
| [`fluxer.dart`](https://github.com/oppahansi/fluxer.dart) | *(this package)* main framework — the `Bot` facade |
| [`fluxer.dart-bot`](https://github.com/oppahansi/fluxer.dart-bot) | example bot |

## Installation

Not yet published to pub.dev. During development, depend on it via a path or
git dependency:

```yaml
dependencies:
  fluxer:
    git:
      url: https://github.com/oppahansi/fluxer.dart.git
```

## License

MIT — see [LICENSE](LICENSE).
