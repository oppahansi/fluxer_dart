import 'dart:async';

import 'package:fluxer_dart/fluxer_dart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockHttpTransport extends Mock implements HttpTransport {}

class MockGatewayConnection extends Mock implements GatewayConnection {}

const _guildId = Snowflake(100);

Map<String, dynamic> _textChannel(String id, String name, int position) => {
  'id': id,
  'type': 0,
  'guild_id': '100',
  'name': name,
  'position': position,
  'permission_overwrites': <dynamic>[],
  'nsfw': false,
  'topic': null,
  'last_message_id': null,
  'rate_limit_per_user': 0,
};

Map<String, dynamic> _member(String id, String username) => {
  'user': {'id': id, 'username': username, 'discriminator': '0001'},
  'nick': null,
  'roles': <dynamic>[],
  'joined_at': '2026-08-12T06:10:10.527Z',
  'mute': false,
  'deaf': false,
  'communication_disabled_until': null,
};

void main() {
  setUpAll(() {
    registerFallbackValue(const HttpTransportRequest(method: 'GET', path: '/'));
  });

  late MockHttpTransport http;
  late MockGatewayConnection connection;
  late StreamController<GatewayEvent> events;
  late StreamController<GatewayConnectionState> states;
  late List<String> requestedPaths;
  late Bot bot;

  setUp(() {
    http = MockHttpTransport();
    connection = MockGatewayConnection();
    events = StreamController<GatewayEvent>.broadcast();
    states = StreamController<GatewayConnectionState>.broadcast();
    requestedPaths = [];

    when(() => connection.events).thenAnswer((_) => events.stream);
    when(() => connection.stateChanges).thenAnswer((_) => states.stream);
    when(() => connection.connect()).thenAnswer((_) async {});
    when(() => connection.dispose()).thenAnswer((_) async {});
    when(() => connection.state).thenReturn(const Disconnected());

    when(() => http.send(any())).thenAnswer((invocation) async {
      final request =
          invocation.positionalArguments.single as HttpTransportRequest;
      requestedPaths.add(request.path);
      if (request.path == '/v1/gateway/bot') {
        return const HttpTransportResponse(
          statusCode: 200,
          headers: {},
          body:
              '{"url": "wss://gateway.fluxer.app", "shards": 1, '
              '"session_start_limit": {"total": 1000, "remaining": 999, '
              '"reset_after": 86400000, "max_concurrency": 1}}',
        );
      }
      return const HttpTransportResponse(
        statusCode: 200,
        headers: {},
        body:
            '{"id":"200","type":0,"guild_id":"100","name":"fetched",'
            '"position":0,"permission_overwrites":[],"nsfw":false,'
            '"topic":null,"last_message_id":null,"rate_limit_per_user":0}',
      );
    });

    bot = Bot(
      token: 't',
      restClient: RestClient(token: 't', transport: http),
      gatewayConnectionFactory: (_, _, _, _) => connection,
    );
  });

  tearDown(() async {
    await bot.dispose();
    await events.close();
    await states.close();
  });

  Future<void> emit(String name, Object payload) async {
    events.add(GatewayEvent.fromDispatch(name, payload));
    await Future<void>.delayed(Duration.zero);
  }

  group('cache', () {
    test('CHANNEL_UPDATE_BULK replaces cached channels in full', () async {
      await bot.login();
      await emit('CHANNEL_UPDATE_BULK', {
        'guild_id': '100',
        'channels': [_textChannel('200', 'moved', 3)],
      });

      final channel = await bot.channel(const Snowflake(200));

      expect((channel as GuildTextChannel).position, 3);
      expect(requestedPaths, ['/v1/gateway/bot']);
    });

    test('CHANNEL_DELETE also drops the threads under it', () async {
      await bot.login();
      await emit('THREAD_CREATE', {
        'id': '300',
        'type': 11,
        'guild_id': '100',
        'parent_id': '200',
        'name': 'orphan',
        'owner_id': '1',
        'last_message_id': null,
        'rate_limit_per_user': 0,
        'flags': 0,
        'member_count': 1,
        'message_count': 0,
        'total_message_sent': 0,
        'thread_metadata': {
          'archived': false,
          'auto_archive_duration': 4320,
          'archive_timestamp': '2026-10-20T17:36:24.580Z',
          'create_timestamp': '2026-10-20T17:36:24.580Z',
          'locked': false,
        },
        'newly_created': true,
      });
      await emit('CHANNEL_DELETE', _textChannel('200', 'parent', 0));

      await bot.channel(const Snowflake(300));

      expect(requestedPaths.last, '/v1/channels/300');
    });

    test('USER_UPDATE replaces the cached user', () async {
      await bot.login();
      await emit('USER_UPDATE', {
        'id': '1',
        'username': 'renamed',
        'discriminator': '0001',
      });

      expect(bot.user(const Snowflake(1))!.username, 'renamed');
    });
  });

  group('queryMembers', () {
    late List<String?> sentNonces;

    setUp(() {
      sentNonces = [];
      when(
        () => connection.requestGuildMembers(
          any(),
          query: any(named: 'query'),
          limit: any(named: 'limit'),
          userIds: any(named: 'userIds'),
          presences: any(named: 'presences'),
          nonce: any(named: 'nonce'),
        ),
      ).thenAnswer((invocation) {
        sentNonces.add(invocation.namedArguments[#nonce] as String?);
      });
    });

    test('collects every chunk of its own answer and caches it', () async {
      await bot.login();
      final result = bot.queryMembers(_guildId, presences: true);
      await Future<void>.delayed(Duration.zero);
      final nonce = sentNonces.single;

      await emit('GUILD_MEMBERS_CHUNK', {
        'guild_id': '100',
        'members': [_member('9', 'someone-else')],
        'chunk_index': 0,
        'chunk_count': 1,
        'nonce': 'not-ours',
      });
      await emit('GUILD_MEMBERS_CHUNK', {
        'guild_id': '100',
        'members': [_member('1', 'a')],
        'chunk_index': 0,
        'chunk_count': 2,
        'nonce': nonce!,
        'presences': [
          {
            'user': {'id': '1', 'username': 'a', 'discriminator': '0001'},
            'status': 'idle',
            'mobile': false,
            'afk': true,
            'custom_status': null,
          },
        ],
      });
      await emit('GUILD_MEMBERS_CHUNK', {
        'guild_id': '100',
        'members': [_member('2', 'b')],
        'chunk_index': 1,
        'chunk_count': 2,
        'nonce': nonce,
      });

      final (:members, :presences) = await result;
      expect(members.map((m) => m.user.username), ['a', 'b']);
      expect(presences.single.status, PresenceStatus.idle);
      expect(bot.user(const Snowflake(2))!.username, 'b');
    });

    test('a matching RATE_LIMITED throws with the retry delay', () async {
      await bot.login();
      final refused = expectLater(
        bot.queryMembers(_guildId),
        throwsA(
          isA<FluxerGatewayRateLimitException>().having(
            (e) => e.retryAfter,
            'retryAfter',
            const Duration(milliseconds: 28498),
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      await emit('RATE_LIMITED', {
        'opcode': 8,
        'retry_after': 28.498,
        'meta': {'guild_id': '100', 'nonce': sentNonces.single!},
      });

      await refused;
    });

    test('each query sends a distinct nonce', () async {
      await bot.login();
      unawaited(
        bot
            .queryMembers(_guildId, timeout: Duration.zero)
            .then((_) {}, onError: (_) {}),
      );
      unawaited(
        bot
            .queryMembers(_guildId, timeout: Duration.zero)
            .then((_) {}, onError: (_) {}),
      );
      await Future<void>.delayed(Duration.zero);

      expect(sentNonces.toSet(), hasLength(2));
    });

    test('rejects input the server would drop silently', () async {
      await bot.login();

      expect(
        () => bot.queryMembers(_guildId, limit: 101),
        throwsA(isA<RangeError>()),
      );
      expect(
        () => bot.queryMembers(
          _guildId,
          userIds: List.generate(101, Snowflake.new),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('needs a gateway session', () {
      expect(() => bot.queryMembers(_guildId), throwsStateError);
    });
  });
}
