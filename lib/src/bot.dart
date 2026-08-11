import 'dart:async';

import 'package:fluxer_gateway/fluxer_gateway.dart';
import 'package:fluxer_rest/fluxer_rest.dart';
import 'package:fluxer_utils/fluxer_utils.dart';

/// The single entry point bot authors interact with — a **Facade** over
/// `fluxer_gateway`'s [GatewayShardManager] and `fluxer_rest`'s
/// [RestClient], so building a bot never requires touching either
/// sub-package's types directly.
///
/// Event listeners can be registered before [login] is called — `events`
/// and the `onXyz` streams are backed by [Bot]'s own persistent broadcast
/// controllers, not the underlying [GatewayShardManager]'s (which doesn't
/// exist yet until [login] resolves the gateway URL and shard count), so
/// the ordering in the class doc example below is safe:
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
    this._gatewayConnectionFactory,
    this.identifyPacing = const Duration(seconds: 5),
  }) : logger = logger ?? const NoopLogger(),
       rest =
           restClient ??
           RestClient(token: token, baseUrl: restBaseUrl, logger: logger);

  final String token;
  final Logger logger;
  final RestClient rest;

  /// Minimum gap between IDENTIFYs of shards sharing the same
  /// `session_start_limit.max_concurrency` bucket — see
  /// [GatewayShardManager].
  final Duration identifyPacing;

  final GatewayConnection Function(
    int shardId,
    int shardCount,
    Uri gatewayUrl,
    String token,
  )?
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
  final _stateController = StreamController<ShardStateChange>.broadcast();
  StreamSubscription<GatewayEvent>? _eventsSubscription;
  StreamSubscription<ShardStateChange>? _stateSubscription;
  GatewayShardManager? _shardManager;

  /// Every gateway dispatch event, from every shard. Empty until [login]
  /// has been called and a READY/RESUMED has come through — see the
  /// `onXyz` streams below for narrowed, more convenient alternatives.
  Stream<GatewayEvent> get events => _eventsController.stream;

  /// Per-shard connection state transitions — see [ShardStateChange].
  Stream<ShardStateChange> get connectionStateChanges =>
      _stateController.stream;

  // Stream has no whereType (that's an Iterable method) — filter+cast by
  // hand, once here rather than 22 times below.
  Stream<T> _narrow<T extends GatewayEvent>() =>
      events.where((e) => e is T).cast<T>();

  Stream<ReadyEvent> get onReady => _narrow();
  Stream<ResumedEvent> get onResumed => _narrow();

  Stream<MessageCreateEvent> get onMessageCreate => _narrow();
  Stream<MessageUpdateEvent> get onMessageUpdate => _narrow();
  Stream<MessageDeleteEvent> get onMessageDelete => _narrow();
  Stream<MessageReactionAddEvent> get onMessageReactionAdd => _narrow();
  Stream<MessageReactionRemoveEvent> get onMessageReactionRemove => _narrow();
  Stream<TypingStartEvent> get onTypingStart => _narrow();

  Stream<GuildCreateEvent> get onGuildCreate => _narrow();
  Stream<GuildUpdateEvent> get onGuildUpdate => _narrow();
  Stream<GuildDeleteEvent> get onGuildDelete => _narrow();
  Stream<GuildRoleCreateEvent> get onGuildRoleCreate => _narrow();
  Stream<GuildRoleUpdateEvent> get onGuildRoleUpdate => _narrow();
  Stream<GuildRoleDeleteEvent> get onGuildRoleDelete => _narrow();
  Stream<GuildMemberAddEvent> get onGuildMemberAdd => _narrow();
  Stream<GuildMemberUpdateEvent> get onGuildMemberUpdate => _narrow();
  Stream<GuildMemberRemoveEvent> get onGuildMemberRemove => _narrow();
  Stream<GuildBanAddEvent> get onGuildBanAdd => _narrow();
  Stream<GuildBanRemoveEvent> get onGuildBanRemove => _narrow();

  Stream<ChannelCreateEvent> get onChannelCreate => _narrow();
  Stream<ChannelUpdateEvent> get onChannelUpdate => _narrow();
  Stream<ChannelDeleteEvent> get onChannelDelete => _narrow();

  /// Shard 0's connection state — the common case for the small,
  /// single-shard deployments most self-hosted Fluxer instances run. For
  /// visibility into every shard, use [connectionStateChanges] or
  /// [shards] directly.
  GatewayConnectionState get connectionState {
    final shards = _shardManager?.shards;
    return shards != null && shards.isNotEmpty
        ? shards.first.state
        : const Disconnected();
  }

  /// Every shard's underlying connection, once [login] has resolved the
  /// shard count — empty before that.
  List<GatewayConnection> get shards => _shardManager?.shards ?? const [];

  /// Looks up the gateway URL and recommended shard count via
  /// `GET /gateway/bot` — never hardcoded, see
  /// [GatewayRestManager.getBotGatewayInfo] — then connects one
  /// [GatewayConnection] per shard.
  Future<void> login() async {
    final info = await _gatewayRest.getBotGatewayInfo();
    final gatewayUrl = Uri.parse(info.url);
    final factory = _gatewayConnectionFactory;
    final manager = GatewayShardManager(
      gatewayUrl: gatewayUrl,
      token: token,
      shardCount: info.shards,
      maxConcurrency: info.sessionStartLimit.maxConcurrency,
      identifyPacing: identifyPacing,
      logger: logger,
      connectionFactory: factory == null
          ? null
          : (shardId, shardCount) =>
                factory(shardId, shardCount, gatewayUrl, token),
    );
    _shardManager = manager;
    _eventsSubscription = manager.events.listen(_eventsController.add);
    _stateSubscription = manager.stateChanges.listen(_stateController.add);
    await manager.connect();
  }

  Future<void> close() async {
    await _eventsSubscription?.cancel();
    await _stateSubscription?.cancel();
    _eventsSubscription = null;
    _stateSubscription = null;
    await _shardManager?.dispose();
    _shardManager = null;
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
