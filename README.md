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
      await bot.messages.send(message.channelId, MessageBuilder(content: 'pong'));
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
`GatewayConnection` ([`fluxer_gateway`](https://github.com/oppahansi/fluxer_gateway))
and a `RestClient` ([`fluxer_rest`](https://github.com/oppahansi/fluxer_rest)),
and exposes:

- Typed per-event streams (`onReady`, `onMessageCreate`, `onGuildCreate`)
  built on top of `fluxer_gateway`'s single `Stream<GatewayEvent>`, so bot
  authors don't need to `switch` on the sealed event hierarchy themselves
  unless they want to.
- Resource managers (`guilds`, `channels`, `messages`) straight from
  `fluxer_rest`.
- `login()` — fetches the current gateway URL via `GET /gateway/bot`
  (never hardcoded — see
  [`GatewayBotInfo`](https://github.com/oppahansi/fluxer_core)'s doc
  comment for why) and connects.

## What's here (v0.1 — M1 slice)

Enough to build the "hello gateway" example bot: login, `onReady`,
`onMessageCreate`, `onGuildCreate`, and the `guilds`/`channels`/`messages`
REST managers. Caching, hydrated convenience objects (e.g. `message.reply()`),
and a command router land in later milestones — see the roadmap in this
ecosystem's planning docs.

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
