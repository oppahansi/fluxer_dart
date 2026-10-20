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

  test('a recipient change evicts the cached group DM', () async {
    await bot.login();
    await emit('CHANNEL_CREATE', {
      'id': '200',
      'type': 3,
      'name': 'group',
      'recipients': <dynamic>[],
      'last_message_id': null,
      'owner_id': '1',
    });
    await bot.channel(const Snowflake(200));
    expect(requestedPaths, ['/v1/gateway/bot']);

    await emit('CHANNEL_RECIPIENT_ADD', {
      'channel_id': '200',
      'user': {'id': '7', 'username': 'joined', 'discriminator': '0001'},
    });
    await bot.channel(const Snowflake(200));

    expect(requestedPaths.last, '/v1/channels/200');
    expect(bot.user(const Snowflake(7))!.username, 'joined');
  });

  test('exposes discovery and the webhook token client', () {
    expect(bot.discovery, isA<DiscoveryRestManager>());
    expect(bot.webhookTokens, isA<WebhookExecuteClient>());
  });
}
