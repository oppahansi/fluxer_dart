import 'dart:async';

import 'package:fluxer/fluxer.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockHttpTransport extends Mock implements HttpTransport {}

class MockGatewayConnection extends Mock implements GatewayConnection {}

const _author = User(
  id: Snowflake(1),
  username: 'someone',
  discriminator: '0',
  globalName: null,
  avatar: null,
  avatarColor: null,
  bot: false,
  system: false,
);

const _botAuthor = User(
  id: Snowflake(2),
  username: 'other-bot',
  discriminator: '0',
  globalName: null,
  avatar: null,
  avatarColor: null,
  bot: true,
  system: false,
);

Message _message(String content, {User author = _author}) => Message(
  id: const Snowflake(10),
  channelId: const Snowflake(20),
  author: author,
  type: 0,
  flags: 0,
  content: content,
  timestamp: DateTime.utc(2026),
  editedTimestamp: null,
  pinned: false,
  mentionEveryone: false,
  tts: false,
  mentions: const [],
  mentionRoleIds: const [],
);

void main() {
  setUpAll(() {
    registerFallbackValue(const HttpTransportRequest(method: 'GET', path: '/'));
  });

  group('CommandRouter', () {
    late MockHttpTransport httpTransport;
    late MockGatewayConnection gatewayConnection;
    late StreamController<GatewayEvent> gatewayEvents;
    late Bot bot;

    setUp(() async {
      httpTransport = MockHttpTransport();
      gatewayConnection = MockGatewayConnection();
      gatewayEvents = StreamController<GatewayEvent>.broadcast();

      when(
        () => gatewayConnection.events,
      ).thenAnswer((_) => gatewayEvents.stream);
      when(
        () => gatewayConnection.stateChanges,
      ).thenAnswer((_) => const Stream<GatewayConnectionState>.empty());
      when(() => gatewayConnection.connect()).thenAnswer((_) async {});
      when(() => gatewayConnection.dispose()).thenAnswer((_) async {});
      when(() => gatewayConnection.state).thenReturn(const Disconnected());
      when(() => httpTransport.send(any())).thenAnswer(
        (_) async => const HttpTransportResponse(
          statusCode: 200,
          headers: {},
          body:
              '{"url": "wss://gateway.fluxer.app", "shards": 1, '
              '"session_start_limit": {"total": 1000, "remaining": 999, "reset_after": 86400000, "max_concurrency": 1}}',
        ),
      );

      bot = Bot(
        token: 'test-token',
        restClient: RestClient(token: 'test-token', transport: httpTransport),
        gatewayConnectionFactory: (shardId, shardCount, url, token) =>
            gatewayConnection,
      );
      await bot.login();
    });

    tearDown(() async {
      await bot.dispose();
      await gatewayEvents.close();
    });

    test('dispatches to the matching command with parsed args', () async {
      final router = CommandRouter(bot: bot, prefix: '!');
      CommandContext? received;
      router.command('echo', (ctx) async => received = ctx);

      gatewayEvents.add(MessageCreateEvent(_message('!echo one two')));
      await Future<void>.delayed(Duration.zero);

      expect(received?.commandName, 'echo');
      expect(received?.args, ['one', 'two']);

      await router.dispose();
    });

    test('args is empty when no arguments were given', () async {
      final router = CommandRouter(bot: bot, prefix: '!');
      CommandContext? received;
      router.command('ping', (ctx) async => received = ctx);

      gatewayEvents.add(MessageCreateEvent(_message('!ping')));
      await Future<void>.delayed(Duration.zero);

      expect(received?.args, isEmpty);

      await router.dispose();
    });

    test('ignores messages without the prefix', () async {
      final router = CommandRouter(bot: bot, prefix: '!');
      var called = false;
      router.command('ping', (ctx) async => called = true);

      gatewayEvents.add(MessageCreateEvent(_message('ping')));
      await Future<void>.delayed(Duration.zero);

      expect(called, isFalse);

      await router.dispose();
    });

    test('ignores unregistered command names', () async {
      final router = CommandRouter(bot: bot, prefix: '!');
      var called = false;
      router.command('ping', (ctx) async => called = true);

      gatewayEvents.add(MessageCreateEvent(_message('!pong')));
      await Future<void>.delayed(Duration.zero);

      expect(called, isFalse);

      await router.dispose();
    });

    test('ignores messages from other bots', () async {
      final router = CommandRouter(bot: bot, prefix: '!');
      var called = false;
      router.command('ping', (ctx) async => called = true);

      gatewayEvents.add(
        MessageCreateEvent(_message('!ping', author: _botAuthor)),
      );
      await Future<void>.delayed(Duration.zero);

      expect(called, isFalse);

      await router.dispose();
    });

    test('a middleware returning false short-circuits the handler', () async {
      final router = CommandRouter(bot: bot, prefix: '!');
      var called = false;
      router.command(
        'ping',
        (ctx) async => called = true,
        middleware: [(ctx) async => false],
      );

      gatewayEvents.add(MessageCreateEvent(_message('!ping')));
      await Future<void>.delayed(Duration.zero);

      expect(called, isFalse);

      await router.dispose();
    });

    test('middleware runs in order before the handler', () async {
      final router = CommandRouter(bot: bot, prefix: '!');
      final order = <String>[];
      router.command(
        'ping',
        (ctx) async => order.add('handler'),
        middleware: [
          (ctx) async {
            order.add('first');
            return true;
          },
          (ctx) async {
            order.add('second');
            return true;
          },
        ],
      );

      gatewayEvents.add(MessageCreateEvent(_message('!ping')));
      await Future<void>.delayed(Duration.zero);

      expect(order, ['first', 'second', 'handler']);

      await router.dispose();
    });

    test('dispose() stops the router from handling further messages', () async {
      final router = CommandRouter(bot: bot, prefix: '!');
      var called = false;
      router.command('ping', (ctx) async => called = true);

      await router.dispose();

      gatewayEvents.add(MessageCreateEvent(_message('!ping')));
      await Future<void>.delayed(Duration.zero);

      expect(called, isFalse);
    });
  });

  group('cooldown', () {
    test('blocks a second call within the window', () async {
      var now = DateTime.utc(2026);
      final middleware = cooldown(const Duration(seconds: 5), now: () => now);
      final context = CommandContext(
        bot: Bot(token: 'unused'),
        message: _message('!ping'),
        commandName: 'ping',
        args: const [],
      );

      expect(await middleware(context), isTrue);

      now = now.add(const Duration(seconds: 2));
      expect(await middleware(context), isFalse);
    });

    test('allows a call again once the window has passed', () async {
      var now = DateTime.utc(2026);
      final middleware = cooldown(const Duration(seconds: 5), now: () => now);
      final context = CommandContext(
        bot: Bot(token: 'unused'),
        message: _message('!ping'),
        commandName: 'ping',
        args: const [],
      );

      expect(await middleware(context), isTrue);

      now = now.add(const Duration(seconds: 6));
      expect(await middleware(context), isTrue);
    });

    test('tracks separate users independently', () async {
      final now = DateTime.utc(2026);
      final middleware = cooldown(const Duration(seconds: 5), now: () => now);

      expect(
        await middleware(
          CommandContext(
            bot: Bot(token: 'unused'),
            message: _message('!ping'),
            commandName: 'ping',
            args: const [],
          ),
        ),
        isTrue,
      );
      expect(
        await middleware(
          CommandContext(
            bot: Bot(token: 'unused'),
            message: _message('!ping', author: _botAuthor),
            commandName: 'ping',
            args: const [],
          ),
        ),
        isTrue,
      );
    });
  });
}
