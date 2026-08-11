import 'dart:async';

import 'package:fluxer/fluxer.dart';
import 'package:fluxer_rest/fluxer_rest.dart';
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
        gatewayConnectionFactory: (url, token) {
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

    test('close() disposes the underlying gateway connection', () async {
      await bot.login();
      await bot.close();

      verify(() => gatewayConnection.dispose()).called(1);
    });
  });
}
