import 'dart:async';

import 'package:fluxer_gateway/fluxer_gateway.dart';
import 'package:fluxer_rest/fluxer_rest.dart';
import 'package:fluxer_utils/fluxer_utils.dart';

/// The single entry point bot authors interact with — a **Facade** over
/// `fluxer_gateway`'s [GatewayConnection] and `fluxer_rest`'s
/// [RestClient], so building a bot never requires touching either
/// sub-package's types directly.
///
/// Event listeners can be registered before [login] is called — `events`
/// and the `onXyz` streams are backed by [Bot]'s own persistent broadcast
/// controllers, not the underlying [GatewayConnection]'s (which doesn't
/// exist yet until [login] resolves the gateway URL), so the ordering in
/// the class doc example below is safe:
///
/// ```dart
/// final bot = Bot(token: 'your-bot-token');
/// bot.onMessageCreate.listen((event) { ... });
/// await bot.login();
/// ```
final class Bot {
  Bot({
    required this.token,
    Uri? restBaseUrl,
    Logger? logger,
    RestClient? restClient,
    GatewayConnection Function(Uri gatewayUrl, String token)?
    gatewayConnectionFactory,
  }) : logger = logger ?? const NoopLogger(),
       rest =
           restClient ??
           RestClient(token: token, baseUrl: restBaseUrl, logger: logger),
       _gatewayConnectionFactory =
           gatewayConnectionFactory ??
           ((url, tok) =>
               GatewayConnection(gatewayUrl: url, token: tok, logger: logger));

  final String token;
  final Logger logger;
  final RestClient rest;

  final GatewayConnection Function(Uri gatewayUrl, String token)
  _gatewayConnectionFactory;

  late final GuildRestManager guilds = GuildRestManager(rest);
  late final ChannelRestManager channels = ChannelRestManager(rest);
  late final MessageRestManager messages = MessageRestManager(rest);
  late final GuildMemberRestManager members = GuildMemberRestManager(rest);
  late final GuildBanRestManager bans = GuildBanRestManager(rest);
  late final GuildEmojiRestManager emojis = GuildEmojiRestManager(rest);
  late final GuildStickerRestManager stickers = GuildStickerRestManager(rest);
  late final GuildRoleRestManager roles = GuildRoleRestManager(rest);
  late final InviteRestManager invites = InviteRestManager(rest);
  late final WebhookRestManager webhooks = WebhookRestManager(rest);
  late final GatewayRestManager _gatewayRest = GatewayRestManager(rest);

  final _eventsController = StreamController<GatewayEvent>.broadcast();
  final _stateController = StreamController<GatewayConnectionState>.broadcast();
  StreamSubscription<GatewayEvent>? _eventsSubscription;
  StreamSubscription<GatewayConnectionState>? _stateSubscription;
  GatewayConnection? _gateway;

  /// Every gateway dispatch event. Empty until [login] has been called
  /// and a READY/RESUMED has come through — see the `onXyz` streams below
  /// for narrowed, more convenient alternatives.
  Stream<GatewayEvent> get events => _eventsController.stream;

  Stream<GatewayConnectionState> get connectionStateChanges =>
      _stateController.stream;

  // Stream has no whereType (that's an Iterable method) — filter+cast by hand.
  Stream<ReadyEvent> get onReady =>
      events.where((e) => e is ReadyEvent).cast<ReadyEvent>();
  Stream<ResumedEvent> get onResumed =>
      events.where((e) => e is ResumedEvent).cast<ResumedEvent>();
  Stream<MessageCreateEvent> get onMessageCreate =>
      events.where((e) => e is MessageCreateEvent).cast<MessageCreateEvent>();
  Stream<GuildCreateEvent> get onGuildCreate =>
      events.where((e) => e is GuildCreateEvent).cast<GuildCreateEvent>();

  GatewayConnectionState get connectionState =>
      _gateway?.state ?? const Disconnected();

  /// Looks up the current gateway URL via `GET /gateway/bot` — never
  /// hardcoded, see [GatewayRestManager.getBotGatewayInfo] — then
  /// connects.
  Future<void> login() async {
    final info = await _gatewayRest.getBotGatewayInfo();
    final gateway = _gatewayConnectionFactory(Uri.parse(info.url), token);
    _gateway = gateway;
    _eventsSubscription = gateway.events.listen(_eventsController.add);
    _stateSubscription = gateway.stateChanges.listen(_stateController.add);
    await gateway.connect();
  }

  Future<void> close() async {
    await _eventsSubscription?.cancel();
    await _stateSubscription?.cancel();
    _eventsSubscription = null;
    _stateSubscription = null;
    await _gateway?.dispose();
    _gateway = null;
  }

  /// Releases everything, including [Bot]'s own event streams — call this
  /// (not just [close]) when the [Bot] instance itself is being disposed,
  /// not just disconnected.
  Future<void> dispose() async {
    await close();
    await _eventsController.close();
    await _stateController.close();
  }
}
