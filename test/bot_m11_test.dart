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
    registerFallbackValue(<Snowflake, GuildSubscription>{});
    registerFallbackValue(const Snowflake(0));
    registerFallbackValue(<Snowflake>[]);
    registerFallbackValue(<ForumUnreadRequest>[]);
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

  Map<String, dynamic> guildState({List<Object> voiceStates = const []}) => {
    'id': '100',
    'properties': {'id': '100', 'name': 'g', 'icon': null, 'owner_id': '1'},
    'roles': <dynamic>[],
    'member_count': 2,
    'online_count': 1,
    'channels': [_textChannel('200', 'from-gateway', 0)],
    'emojis': <dynamic>[],
    'stickers': <dynamic>[],
    'members': [_member('9', 'self')],
    'voice_states': voiceStates,
    'joined_at': '2026-08-12T06:10:10.527Z',
  };

  Map<String, dynamic> voice(String connection, String? channel) => {
    'guild_id': '100',
    'channel_id': channel,
    'user_id': '9',
    'connection_id': connection,
    'session_id': 's',
    'member': null,
  };

  Map<String, dynamic> presence(String status, {String? guild}) => {
    'user': {'id': '7', 'username': 'p', 'discriminator': '0001'},
    'status': status,
    'mobile': false,
    'afk': false,
    'custom_status': null,
    'guild_id': ?guild,
  };

  group('guild state cache', () {
    test(
      'GUILD_CREATE caches its channels, so channel() needs no fetch',
      () async {
        await bot.login();
        await emit('GUILD_CREATE', guildState());

        final channel = await bot.channel(const Snowflake(200));

        expect(channel.name, 'from-gateway');
        expect(requestedPaths, ['/v1/gateway/bot']);
        expect(bot.user(const Snowflake(9))!.username, 'self');
        expect((await bot.guild(_guildId)).onlineCount, 1);
      },
    );

    test('GUILD_SYNC replaces the voice states of its guild', () async {
      await bot.login();
      await emit('GUILD_CREATE', guildState(voiceStates: [voice('a', '200')]));
      expect(bot.voiceStates(_guildId).single.connectionId, 'a');

      await emit('GUILD_SYNC', guildState(voiceStates: [voice('b', '200')]));

      expect(bot.voiceStates(_guildId).map((v) => v.connectionId), ['b']);
    });

    test(
      'VOICE_STATE_UPDATE adds a connection and a null channel removes it',
      () async {
        await bot.login();
        await emit('VOICE_STATE_UPDATE', voice('a', '200'));
        await emit('VOICE_STATE_UPDATE', voice('b', '200'));
        expect(bot.voiceStates(_guildId), hasLength(2));

        await emit('VOICE_STATE_UPDATE', voice('a', null));

        expect(bot.voiceStates(_guildId).map((v) => v.connectionId), ['b']);
      },
    );
  });

  group('presence cache', () {
    test('PRESENCE_UPDATE with a guild is cached under it', () async {
      await bot.login();
      await emit('PRESENCE_UPDATE', presence('dnd', guild: '100'));

      expect(
        bot.presence(_guildId, const Snowflake(7))!.status,
        PresenceStatus.doNotDisturb,
      );
    });

    test('a member list caches members and their presences', () async {
      await bot.login();
      await emit('GUILD_MEMBER_LIST_UPDATE', {
        'guild_id': '100',
        'id': '200',
        'member_count': 1,
        'online_count': 1,
        'groups': [
          {'id': 'online', 'count': 1},
        ],
        'ops': [
          {
            'op': 'SYNC',
            'range': [0, 99],
            'items': [
              {
                'group': {'id': 'online', 'count': 1},
              },
              {
                'member': {..._member('7', 'p'), 'presence': presence('idle')},
              },
            ],
          },
        ],
      });

      expect(
        bot.presence(_guildId, const Snowflake(7))!.status,
        PresenceStatus.idle,
      );
      expect(
        (await bot.member(_guildId, const Snowflake(7))).user.username,
        'p',
      );
      expect(requestedPaths, ['/v1/gateway/bot']);
    });
  });

  group('requests', () {
    late List<Map<Snowflake, GuildSubscription>> subscriptions;
    late List<String?> countNonces;

    setUp(() {
      subscriptions = [];
      countNonces = [];
      when(() => connection.lazyRequest(any())).thenAnswer((invocation) {
        subscriptions.add(
          invocation.positionalArguments.single
              as Map<Snowflake, GuildSubscription>,
        );
      });
      when(
        () => connection.requestGuildCounts(any(), nonce: any(named: 'nonce')),
      ).thenAnswer((invocation) {
        countNonces.add(invocation.namedArguments[#nonce] as String?);
      });
      when(
        () => connection.requestChannelMemberCounts(
          any(),
          any(),
          nonce: any(named: 'nonce'),
        ),
      ).thenAnswer((invocation) {
        countNonces.add(invocation.namedArguments[#nonce] as String?);
      });
      when(
        () => connection.requestForumUnreads(any(), any(), any()),
      ).thenAnswer((_) {});
    });

    test('subscribe sends a Lazy Request for that guild', () async {
      await bot.login();

      bot.subscribe(_guildId, const GuildSubscription(members: [Snowflake(7)]));

      expect(subscriptions.single.keys, [_guildId]);
      expect(subscriptions.single[_guildId]!.members, [const Snowflake(7)]);
    });

    test('guildCounts ignores answers to other requests', () async {
      await bot.login();
      final result = bot.guildCounts([_guildId]);
      await Future<void>.delayed(Duration.zero);

      await emit('GUILD_COUNTS_UPDATE', {
        'counts': <dynamic>[],
        'nonce': 'someone-else',
      });
      await emit('GUILD_COUNTS_UPDATE', {
        'counts': [
          {'guild_id': '100', 'member_count': 2, 'online_count': 1},
        ],
        'nonce': countNonces.single!,
      });

      expect((await result).single.memberCount, 2);
    });

    test('channelMemberCounts matches its nonce', () async {
      await bot.login();
      final result = bot.channelMemberCounts(_guildId, [const Snowflake(200)]);
      await Future<void>.delayed(Duration.zero);

      await emit('CHANNEL_MEMBER_COUNTS_UPDATE', {
        'counts': [
          {
            'guild_id': '100',
            'channel_id': '200',
            'member_count': 2,
            'online_count': 2,
          },
        ],
        'nonce': countNonces.single!,
      });

      expect((await result).single.channelId, const Snowflake(200));
    });

    test('forumUnreads matches the answer by channel', () async {
      await bot.login();
      final result = bot.forumUnreads(_guildId, const Snowflake(300), [
        const ForumUnreadRequest(Snowflake(301)),
      ]);
      await Future<void>.delayed(Duration.zero);

      await emit('FORUM_UNREADS', {
        'guild_id': '100',
        'channel_id': '999',
        'threads': <dynamic>[],
      });
      await emit('FORUM_UNREADS', {
        'guild_id': '100',
        'channel_id': '300',
        'threads': [
          {'thread_id': '301', 'missing': true},
        ],
      });

      expect((await result).single.missing, isTrue);
    });

    test('need a gateway session', () {
      expect(
        () => bot.subscribe(_guildId, const GuildSubscription()),
        throwsStateError,
      );
      expect(() => bot.guildCounts([_guildId]), throwsStateError);
    });
  });
}
