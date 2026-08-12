import 'package:fluxer_dart/fluxer_dart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockHttpTransport extends Mock implements HttpTransport {}

void main() {
  setUpAll(() {
    registerFallbackValue(const HttpTransportRequest(method: 'GET', path: '/'));
  });

  group('requireGuildPermission', () {
    const guildId = Snowflake(100);
    const channelId = Snowflake(200);
    const ownerId = Snowflake(1);
    const memberId = Snowflake(300);

    late MockHttpTransport httpTransport;
    late Bot bot;
    late List<String> requestedPaths;

    User authorWith({required Snowflake id}) => User(
      id: id,
      username: 'someone',
      discriminator: '0',
      globalName: null,
      avatar: null,
      avatarColor: null,
      bot: false,
      system: false,
    );

    Message messageFrom(Snowflake authorId) => Message(
      id: const Snowflake(1),
      channelId: channelId,
      author: authorWith(id: authorId),
      type: 0,
      flags: 0,
      content: '!ban',
      timestamp: DateTime.utc(2026),
      editedTimestamp: null,
      pinned: false,
      mentionEveryone: false,
      tts: false,
      mentions: const [],
      mentionRoleIds: const [],
    );

    void stubTransport({required String rolePermissions}) {
      when(() => httpTransport.send(any())).thenAnswer((invocation) async {
        final request =
            invocation.positionalArguments[0] as HttpTransportRequest;
        requestedPaths.add(request.path);
        return switch (request.path) {
          '/guilds/$guildId' => HttpTransportResponse(
            statusCode: 200,
            headers: const {},
            body:
                '{"id": "100", "name": "g", "icon": null, '
                '"owner_id": "$ownerId", "roles": [], "member_count": 1}',
          ),
          '/channels/$channelId' => const HttpTransportResponse(
            statusCode: 200,
            headers: {},
            body:
                '{"id": "200", "type": 0, "name": "c", '
                '"guild_id": "100", "topic": null, "position": 0, '
                '"parent_id": null, "last_message_id": null, "nsfw": false, '
                '"rate_limit_per_user": 0}',
          ),
          '/guilds/$guildId/members/$memberId' => const HttpTransportResponse(
            statusCode: 200,
            headers: {},
            body:
                '{"user": {"id": "300", "username": "m", "discriminator": "0", '
                '"global_name": null, "avatar": null, "avatar_color": null, '
                '"bot": false, "system": false}, "nick": null, "avatar": null, '
                '"roles": ["400"], "joined_at": "2026-01-01T00:00:00.000Z", '
                '"mute": false, "deaf": false, "communication_disabled_until": null}',
          ),
          '/guilds/$guildId/members/$ownerId' => const HttpTransportResponse(
            statusCode: 200,
            headers: {},
            body:
                '{"user": {"id": "1", "username": "owner", "discriminator": "0", '
                '"global_name": null, "avatar": null, "avatar_color": null, '
                '"bot": false, "system": false}, "nick": null, "avatar": null, '
                '"roles": [], "joined_at": "2026-01-01T00:00:00.000Z", '
                '"mute": false, "deaf": false, "communication_disabled_until": null}',
          ),
          '/guilds/$guildId/roles' => HttpTransportResponse(
            statusCode: 200,
            headers: const {},
            body:
                '[{"id": "100", "name": "@everyone", "color": 0, "position": 0, '
                '"permissions": "0", "hoist": false, "mentionable": false}, '
                '{"id": "400", "name": "role", "color": 0, "position": 1, '
                '"permissions": "$rolePermissions", "hoist": false, "mentionable": false}]',
          ),
          '/channels/$channelId/messages' => const HttpTransportResponse(
            statusCode: 200,
            headers: {},
            body:
                '{"id": "2", "channel_id": "200", "author": {"id": "999", '
                '"username": "bot", "discriminator": "0", "global_name": null, '
                '"avatar": null, "avatar_color": null, "bot": true, "system": false}, '
                '"type": 0, "flags": 0, "content": "denied", "timestamp": '
                '"2026-01-01T00:00:00.000Z", "edited_timestamp": null, "pinned": false, '
                '"mention_everyone": false, "tts": false, "mentions": [], "mention_roles": []}',
          ),
          _ => throw StateError('unexpected request: ${request.path}'),
        };
      });
    }

    setUp(() {
      httpTransport = MockHttpTransport();
      requestedPaths = [];
      bot = Bot(
        token: 'test-token',
        restClient: RestClient(token: 'test-token', transport: httpTransport),
      );
    });

    test('allows the guild owner regardless of role permissions', () async {
      stubTransport(rolePermissions: '0');
      final middleware = requireGuildPermission(PermissionFlag.banMembers);
      final context = CommandContext(
        bot: bot,
        message: messageFrom(ownerId),
        commandName: 'ban',
        args: const [],
      );

      expect(await middleware(context), isTrue);
    });

    test('allows a member whose role grants the required permission', () async {
      stubTransport(rolePermissions: PermissionFlag.banMembers.bit.toString());
      final middleware = requireGuildPermission(PermissionFlag.banMembers);
      final context = CommandContext(
        bot: bot,
        message: messageFrom(memberId),
        commandName: 'ban',
        args: const [],
      );

      expect(await middleware(context), isTrue);
    });

    test(
      'denies a member without the required permission and replies why',
      () async {
        stubTransport(rolePermissions: '0');
        final middleware = requireGuildPermission(PermissionFlag.banMembers);
        final context = CommandContext(
          bot: bot,
          message: messageFrom(memberId),
          commandName: 'ban',
          args: const [],
        );

        expect(await middleware(context), isFalse);
        expect(requestedPaths, contains('/channels/$channelId/messages'));
      },
    );
  });
}
