import 'dart:async';

import 'package:fluxer_dart/fluxer_dart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockHttpTransport extends Mock implements HttpTransport {}

class MockGatewayConnection extends Mock implements GatewayConnection {}

void main() {
  setUpAll(() {
    registerFallbackValue(const HttpTransportRequest(method: 'GET', path: '/'));
  });

  group('Bot', () {
    late MockHttpTransport httpTransport;
    late MockGatewayConnection gatewayConnection;
    late StreamController<GatewayEvent> gatewayEvents;
    late StreamController<GatewayConnectionState> gatewayStates;
    late List<Uri> requestedGatewayUrls;
    late List<String> requestedTokens;
    late Bot bot;

    setUp(() {
      httpTransport = MockHttpTransport();
      gatewayConnection = MockGatewayConnection();
      gatewayEvents = StreamController<GatewayEvent>.broadcast();
      gatewayStates = StreamController<GatewayConnectionState>.broadcast();
      requestedGatewayUrls = [];
      requestedTokens = [];

      when(
        () => gatewayConnection.events,
      ).thenAnswer((_) => gatewayEvents.stream);
      when(
        () => gatewayConnection.stateChanges,
      ).thenAnswer((_) => gatewayStates.stream);
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
        gatewayConnectionFactory: (shardId, shardCount, url, token) {
          requestedGatewayUrls.add(url);
          requestedTokens.add(token);
          return gatewayConnection;
        },
      );
    });

    tearDown(() async {
      await bot.dispose();
      await gatewayEvents.close();
      await gatewayStates.close();
    });

    test('connectionState is Disconnected before login', () {
      expect(bot.connectionState, isA<Disconnected>());
    });

    test('exposes the guild-scoped REST managers', () {
      expect(bot.members, isA<GuildMemberRestManager>());
      expect(bot.bans, isA<GuildBanRestManager>());
      expect(bot.emojis, isA<GuildEmojiRestManager>());
      expect(bot.stickers, isA<GuildStickerRestManager>());
      expect(bot.roles, isA<GuildRoleRestManager>());
      expect(bot.invites, isA<InviteRestManager>());
      expect(bot.webhooks, isA<WebhookRestManager>());
    });

    test(
      'login() resolves the gateway URL via REST, then builds and connects the gateway',
      () async {
        await bot.login();

        expect(requestedGatewayUrls, [Uri.parse('wss://gateway.fluxer.app')]);
        expect(requestedTokens, ['test-token']);
        verify(() => gatewayConnection.connect()).called(1);
      },
    );

    test(
      'onMessageCreate forwards MessageCreateEvent from the underlying gateway',
      () async {
        await bot.login();

        final received = <MessageCreateEvent>[];
        bot.onMessageCreate.listen(received.add);

        final event = MessageCreateEvent(
          Message(
            id: Snowflake.parse('1'),
            channelId: Snowflake.parse('2'),
            author: const User(
              id: Snowflake(3),
              username: 'someone',
              discriminator: '0',
              globalName: null,
              avatar: null,
              avatarColor: null,
              bot: false,
              system: false,
            ),
            type: 0,
            flags: 0,
            content: '!ping',
            timestamp: DateTime.now(),
            editedTimestamp: null,
            pinned: false,
            mentionEveryone: false,
            tts: false,
            mentions: const [],
            mentionRoleIds: const [],
          ),
        );
        gatewayEvents.add(event);
        await Future<void>.delayed(Duration.zero);

        expect(received, [event]);
      },
    );

    test(
      'the narrowed onXyz streams only deliver their own event type, not siblings',
      () async {
        await bot.login();

        final messageDeletes = <MessageDeleteEvent>[];
        final channelDeletes = <ChannelDeleteEvent>[];
        bot.onMessageDelete.listen(messageDeletes.add);
        bot.onChannelDelete.listen(channelDeletes.add);

        gatewayEvents.add(
          const MessageDeleteEvent(
            messageId: Snowflake(1),
            channelId: Snowflake(2),
          ),
        );
        gatewayEvents.add(
          const ChannelDeleteEvent(
            channelId: Snowflake(3),
            channelType: ChannelType.guildText,
            guildId: null,
          ),
        );
        await Future<void>.delayed(Duration.zero);

        expect(messageDeletes, hasLength(1));
        expect(channelDeletes, hasLength(1));
      },
    );

    test(
      'listeners registered before login() still receive events after it',
      () async {
        final received = <ReadyEvent>[];
        bot.onReady.listen(received.add);

        await bot.login();
        final readyEvent = ReadyEvent(
          sessionId: 's1',
          user: const User(
            id: Snowflake(1),
            username: 'bot',
            discriminator: '0',
            globalName: null,
            avatar: null,
            avatarColor: null,
            bot: true,
            system: false,
          ),
        );
        gatewayEvents.add(readyEvent);
        await Future<void>.delayed(Duration.zero);

        expect(received, [readyEvent]);
      },
    );

    test('selfId is populated once READY comes through', () async {
      expect(bot.selfId, isNull);
      await bot.login();

      gatewayEvents.add(
        ReadyEvent(
          sessionId: 's1',
          user: const User(
            id: Snowflake(42),
            username: 'bot',
            discriminator: '0',
            globalName: null,
            avatar: null,
            avatarColor: null,
            bot: true,
            system: false,
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(bot.selfId, const Snowflake(42));
    });

    test('close() disposes the underlying gateway connection', () async {
      await bot.login();
      await bot.close();

      verify(() => gatewayConnection.dispose()).called(1);
    });
  });

  group('Bot caching', () {
    late MockHttpTransport httpTransport;
    late MockGatewayConnection gatewayConnection;
    late StreamController<GatewayEvent> gatewayEvents;
    late List<String> requestedPaths;
    late Bot bot;

    const guildId = Snowflake(100);
    const channelId = Snowflake(200);
    const userId = Snowflake(300);

    setUp(() {
      httpTransport = MockHttpTransport();
      gatewayConnection = MockGatewayConnection();
      gatewayEvents = StreamController<GatewayEvent>.broadcast();
      requestedPaths = [];

      when(
        () => gatewayConnection.events,
      ).thenAnswer((_) => gatewayEvents.stream);
      when(
        () => gatewayConnection.stateChanges,
      ).thenAnswer((_) => const Stream<GatewayConnectionState>.empty());
      when(() => gatewayConnection.connect()).thenAnswer((_) async {});
      when(() => gatewayConnection.dispose()).thenAnswer((_) async {});
      when(() => gatewayConnection.state).thenReturn(const Disconnected());

      when(() => httpTransport.send(any())).thenAnswer((invocation) async {
        final request =
            invocation.positionalArguments[0] as HttpTransportRequest;
        requestedPaths.add(request.path);
        return switch (request.path) {
          '/gateway/bot' => const HttpTransportResponse(
            statusCode: 200,
            headers: {},
            body:
                '{"url": "wss://gateway.fluxer.app", "shards": 1, '
                '"session_start_limit": {"total": 1000, "remaining": 999, "reset_after": 86400000, "max_concurrency": 1}}',
          ),
          '/guilds/$guildId' => const HttpTransportResponse(
            statusCode: 200,
            headers: {},
            body:
                '{"id": "100", "name": "fetched guild", "icon": null, '
                '"owner_id": "1", "roles": [], "member_count": 1}',
          ),
          '/channels/$channelId' => const HttpTransportResponse(
            statusCode: 200,
            headers: {},
            body:
                '{"id": "200", "type": 0, "name": "fetched-channel", '
                '"guild_id": "100", "topic": null, "position": 0, '
                '"parent_id": null, "last_message_id": null, "nsfw": false, '
                '"rate_limit_per_user": 0}',
          ),
          '/guilds/$guildId/members/$userId' => const HttpTransportResponse(
            statusCode: 200,
            headers: {},
            body:
                '{"user": {"id": "300", "username": "fetched", '
                '"discriminator": "0", "global_name": null, "avatar": null, '
                '"avatar_color": null, "bot": false, "system": false}, '
                '"nick": null, "avatar": null, "roles": [], '
                '"joined_at": "2026-01-01T00:00:00.000Z", "mute": false, '
                '"deaf": false, "communication_disabled_until": null}',
          ),
          _ => throw StateError('unexpected request: ${request.path}'),
        };
      });

      bot = Bot(
        token: 'test-token',
        restClient: RestClient(token: 'test-token', transport: httpTransport),
        gatewayConnectionFactory: (shardId, shardCount, url, token) =>
            gatewayConnection,
      );
    });

    tearDown(() async {
      await bot.dispose();
      await gatewayEvents.close();
    });

    const user = User(
      id: userId,
      username: 'someone',
      discriminator: '0',
      globalName: null,
      avatar: null,
      avatarColor: null,
      bot: false,
      system: false,
    );

    test(
      'guild() returns the GUILD_CREATE-cached guild without hitting REST',
      () async {
        await bot.login();
        const guild = Guild(
          id: guildId,
          name: 'cached guild',
          icon: null,
          ownerId: Snowflake(1),
          roles: [],
          memberCount: 1,
          onlineCount: null,
          vanityUrlCode: null,
        );
        gatewayEvents.add(GuildCreateEvent(guild));
        await Future<void>.delayed(Duration.zero);

        final result = await bot.guild(guildId);

        expect(result.name, 'cached guild');
        expect(requestedPaths, ['/gateway/bot']);
      },
    );

    test(
      'guild() falls back to REST on a cache miss and caches the result',
      () async {
        await bot.login();

        final first = await bot.guild(guildId);
        final second = await bot.guild(guildId);

        expect(first.name, 'fetched guild');
        expect(identical(first, second), isTrue);
        expect(requestedPaths, ['/gateway/bot', '/guilds/$guildId']);
      },
    );

    test('GUILD_DELETE evicts the guild so guild() re-fetches', () async {
      await bot.login();
      const guild = Guild(
        id: guildId,
        name: 'cached guild',
        icon: null,
        ownerId: Snowflake(1),
        roles: [],
        memberCount: 1,
        onlineCount: null,
        vanityUrlCode: null,
      );
      gatewayEvents.add(GuildCreateEvent(guild));
      await Future<void>.delayed(Duration.zero);

      gatewayEvents.add(
        const GuildDeleteEvent(guildId: guildId, unavailable: null),
      );
      await Future<void>.delayed(Duration.zero);

      final result = await bot.guild(guildId);

      expect(result.name, 'fetched guild');
      expect(requestedPaths, ['/gateway/bot', '/guilds/$guildId']);
    });

    test('CHANNEL_UPDATE evicts the channel so channel() re-fetches', () async {
      await bot.login();
      const channel = GuildTextChannel(
        id: channelId,
        name: 'cached-channel',
        guildId: guildId,
        topic: null,
        position: 0,
        parentId: null,
        lastMessageId: null,
        nsfw: false,
        rateLimitPerUser: 0,
      );
      gatewayEvents.add(ChannelCreateEvent(channel));
      await Future<void>.delayed(Duration.zero);

      gatewayEvents.add(
        ChannelUpdateEvent(
          channelId: channelId,
          channelType: ChannelType.guildText,
          data: const {},
        ),
      );
      await Future<void>.delayed(Duration.zero);

      final result = await bot.channel(channelId);

      expect(result, isA<GuildTextChannel>());
      expect((result as GuildTextChannel).name, 'fetched-channel');
      expect(requestedPaths, ['/gateway/bot', '/channels/$channelId']);
    });

    test(
      'member() returns the GUILD_MEMBER_ADD-cached member without hitting REST',
      () async {
        await bot.login();
        final member = GuildMember(
          user: user,
          nick: 'cached nick',
          avatar: null,
          roleIds: const [],
          joinedAt: DateTime.utc(2026),
          mute: false,
          deaf: false,
          communicationDisabledUntil: null,
        );
        gatewayEvents.add(
          GuildMemberAddEvent(guildId: guildId, member: member),
        );
        await Future<void>.delayed(Duration.zero);

        final result = await bot.member(guildId, userId);

        expect(result.nick, 'cached nick');
        expect(requestedPaths, ['/gateway/bot']);
      },
    );

    test(
      'GUILD_MEMBER_REMOVE evicts the member so member() re-fetches',
      () async {
        await bot.login();
        final member = GuildMember(
          user: user,
          nick: 'cached nick',
          avatar: null,
          roleIds: const [],
          joinedAt: DateTime.utc(2026),
          mute: false,
          deaf: false,
          communicationDisabledUntil: null,
        );
        gatewayEvents.add(
          GuildMemberAddEvent(guildId: guildId, member: member),
        );
        await Future<void>.delayed(Duration.zero);

        gatewayEvents.add(
          GuildMemberRemoveEvent(guildId: guildId, userId: userId),
        );
        await Future<void>.delayed(Duration.zero);

        final result = await bot.member(guildId, userId);

        expect(result.nick, isNull);
        expect(requestedPaths, [
          '/gateway/bot',
          '/guilds/$guildId/members/$userId',
        ]);
      },
    );

    test(
      'user() returns null until a MESSAGE_CREATE (or similar) has surfaced them',
      () async {
        await bot.login();
        expect(bot.user(userId), isNull);

        gatewayEvents.add(
          MessageCreateEvent(
            Message(
              id: const Snowflake(1),
              channelId: channelId,
              author: user,
              type: 0,
              flags: 0,
              content: 'hi',
              timestamp: DateTime.utc(2026),
              editedTimestamp: null,
              pinned: false,
              mentionEveryone: false,
              tts: false,
              mentions: const [],
              mentionRoleIds: const [],
            ),
          ),
        );
        await Future<void>.delayed(Duration.zero);

        expect(bot.user(userId)?.username, 'someone');
      },
    );

    test('reply() sends to the message\'s own channel', () async {
      await bot.login();
      final message = Message(
        id: const Snowflake(1),
        channelId: channelId,
        author: user,
        type: 0,
        flags: 0,
        content: 'hi',
        timestamp: DateTime.utc(2026),
        editedTimestamp: null,
        pinned: false,
        mentionEveryone: false,
        tts: false,
        mentions: const [],
        mentionRoleIds: const [],
      );

      when(() => httpTransport.send(any())).thenAnswer((invocation) async {
        final request =
            invocation.positionalArguments[0] as HttpTransportRequest;
        requestedPaths.add(request.path);
        return const HttpTransportResponse(
          statusCode: 200,
          headers: {},
          body:
              '{"id": "2", "channel_id": "200", "author": {"id": "300", '
              '"username": "someone", "discriminator": "0", "global_name": null, '
              '"avatar": null, "avatar_color": null, "bot": false, "system": false}, '
              '"type": 0, "flags": 0, "content": "pong", "timestamp": '
              '"2026-01-01T00:00:00.000Z", "edited_timestamp": null, "pinned": false, '
              '"mention_everyone": false, "tts": false, "mentions": [], "mention_roles": []}',
        );
      });

      final sent = await bot.reply(message, MessageBuilder(content: 'pong'));

      expect(sent.content, 'pong');
      expect(requestedPaths.last, '/channels/$channelId/messages');
    });
  });

  group('Bot with multiple shards', () {
    test(
      'login() builds one GatewayConnection per shard, each with its own shardId',
      () async {
        final httpTransport = MockHttpTransport();
        when(() => httpTransport.send(any())).thenAnswer(
          (_) async => const HttpTransportResponse(
            statusCode: 200,
            headers: {},
            body:
                '{"url": "wss://gateway.fluxer.app", "shards": 3, '
                '"session_start_limit": {"total": 1000, "remaining": 999, "reset_after": 86400000, "max_concurrency": 3}}',
          ),
        );

        final requestedShardIds = <int>[];
        final requestedShardCounts = <int>[];
        final mocks = <MockGatewayConnection>[];

        final bot = Bot(
          token: 'test-token',
          restClient: RestClient(token: 'test-token', transport: httpTransport),
          gatewayConnectionFactory: (shardId, shardCount, url, token) {
            requestedShardIds.add(shardId);
            requestedShardCounts.add(shardCount);
            final mock = MockGatewayConnection();
            when(
              () => mock.events,
            ).thenAnswer((_) => const Stream<GatewayEvent>.empty());
            when(
              () => mock.stateChanges,
            ).thenAnswer((_) => const Stream<GatewayConnectionState>.empty());
            when(() => mock.connect()).thenAnswer((_) async {});
            when(() => mock.dispose()).thenAnswer((_) async {});
            when(() => mock.state).thenReturn(const Disconnected());
            mocks.add(mock);
            return mock;
          },
        );

        await bot.login();

        expect(requestedShardIds, [0, 1, 2]);
        expect(requestedShardCounts, [3, 3, 3]);
        expect(bot.shards, hasLength(3));
        for (final mock in mocks) {
          verify(() => mock.connect()).called(1);
        }

        await bot.dispose();
      },
    );
  });
}
