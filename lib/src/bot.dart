import 'dart:async';

import 'package:fluxer_dart_core/fluxer_dart_core.dart';
import 'package:fluxer_dart_gateway/fluxer_dart_gateway.dart';
import 'package:fluxer_dart_rest/fluxer_dart_rest.dart';
import 'package:fluxer_dart_utils/fluxer_dart_utils.dart';

/// The single entry point bot authors interact with — a **Facade** over
/// `fluxer_dart_gateway`'s [GatewayShardManager] and `fluxer_dart_rest`'s
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
    CacheProvider<Snowflake, Guild>? guildCache,
    CacheProvider<Snowflake, Channel>? channelCache,
    CacheProvider<Snowflake, User>? userCache,
    CacheProvider<(Snowflake, Snowflake), GuildMember>? memberCache,
  }) : logger = logger ?? const NoopLogger(),
       rest =
           restClient ??
           RestClient(token: token, baseUrl: restBaseUrl, logger: logger),
       _guildCache = guildCache ?? InMemoryCacheProvider(),
       _channelCache = channelCache ?? InMemoryCacheProvider(),
       _userCache = userCache ?? InMemoryCacheProvider(),
       _memberCache = memberCache ?? InMemoryCacheProvider();

  final String token;
  final Logger logger;
  final RestClient rest;

  final CacheProvider<Snowflake, Guild> _guildCache;
  final CacheProvider<Snowflake, Channel> _channelCache;
  final CacheProvider<Snowflake, User> _userCache;
  final CacheProvider<(Snowflake, Snowflake), GuildMember> _memberCache;

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
    _eventsSubscription = manager.events.listen(_handleEvent);
    _stateSubscription = manager.stateChanges.listen(_stateController.add);
    await manager.connect();
  }

  /// Updates the guild/channel/user/member caches from whatever a dispatch
  /// event happens to carry, then forwards the event unchanged. Role and
  /// ban events aren't reflected here: [Guild] has no mutable roles view
  /// to patch in place, and bans aren't cached at all — both are still
  /// available fresh via [roles]/[GuildBanRestManager] directly.
  ///
  /// `*_UPDATE` events that carry only a partial payload
  /// ([ChannelUpdateEvent]) remove the stale cache entry rather than risk
  /// caching incomplete data — the next [channel] call re-fetches it.
  void _handleEvent(GatewayEvent event) {
    switch (event) {
      case ReadyEvent(:final user):
        _userCache.set(user.id, user);
      case GuildCreateEvent(:final guild):
        _guildCache.set(guild.id, guild);
      case GuildUpdateEvent(:final guild):
        _guildCache.set(guild.id, guild);
      case GuildDeleteEvent(:final guildId):
        _guildCache.remove(guildId);
      case ChannelCreateEvent(:final channel):
        _channelCache.set(channel.id, channel);
      case ChannelUpdateEvent(:final channelId):
        _channelCache.remove(channelId);
      case ChannelDeleteEvent(:final channelId):
        _channelCache.remove(channelId);
      case GuildMemberAddEvent(:final guildId, :final member):
        _memberCache.set((guildId, member.user.id), member);
        _userCache.set(member.user.id, member.user);
      case GuildMemberUpdateEvent(:final guildId, :final member):
        _memberCache.set((guildId, member.user.id), member);
        _userCache.set(member.user.id, member.user);
      case GuildMemberRemoveEvent(:final guildId, :final userId):
        _memberCache.remove((guildId, userId));
      case MessageCreateEvent(:final message):
        _userCache.set(message.author.id, message.author);
      case ResumedEvent():
      case MessageUpdateEvent():
      case MessageDeleteEvent():
      case MessageReactionAddEvent():
      case MessageReactionRemoveEvent():
      case TypingStartEvent():
      case GuildRoleCreateEvent():
      case GuildRoleUpdateEvent():
      case GuildRoleDeleteEvent():
      case GuildBanAddEvent():
      case GuildBanRemoveEvent():
      case UnknownDispatchEvent():
        break;
    }
    _eventsController.add(event);
  }

  /// [userId]'s cached [User], or `null` if it hasn't been seen yet —
  /// there's no `GET /users/{id}` manager to fall back to, unlike
  /// [guild]/[channel]/[member], so this is cache-only.
  User? user(Snowflake userId) => _userCache.get(userId);

  /// [guildId]'s [Guild], from cache if present, otherwise fetched via
  /// [guilds] and cached for next time.
  Future<Guild> guild(Snowflake guildId) async {
    final cached = _guildCache.get(guildId);
    if (cached != null) return cached;
    final fetched = await guilds.get(guildId);
    _guildCache.set(guildId, fetched);
    return fetched;
  }

  /// [channelId]'s [Channel], from cache if present, otherwise fetched via
  /// [channels] and cached for next time.
  Future<Channel> channel(Snowflake channelId) async {
    final cached = _channelCache.get(channelId);
    if (cached != null) return cached;
    final fetched = await channels.get(channelId);
    _channelCache.set(channelId, fetched);
    return fetched;
  }

  /// [userId]'s [GuildMember] in [guildId], from cache if present,
  /// otherwise fetched via [members] and cached for next time.
  Future<GuildMember> member(Snowflake guildId, Snowflake userId) async {
    final cached = _memberCache.get((guildId, userId));
    if (cached != null) return cached;
    final fetched = await members.get(guildId, userId);
    _memberCache.set((guildId, userId), fetched);
    return fetched;
  }

  /// Sends [builder] to the channel [message] was posted in.
  Future<Message> reply(Message message, MessageBuilder builder) =>
      messages.send(message.channelId, builder);

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
