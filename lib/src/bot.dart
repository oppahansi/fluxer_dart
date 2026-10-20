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
    CacheProvider<(Snowflake, Snowflake), UserPresence>? presenceCache,
    CacheProvider<String, VoiceState>? voiceStateCache,
    this.ignoredEvents = const {},
    this.initialPresence,
    this.sessionFlags = SessionFlags.none,
  }) : logger = logger ?? const NoopLogger(),
       rest =
           restClient ??
           RestClient(token: token, baseUrl: restBaseUrl, logger: logger),
       _guildCache = guildCache ?? InMemoryCacheProvider(),
       _channelCache = channelCache ?? InMemoryCacheProvider(),
       _userCache = userCache ?? InMemoryCacheProvider(),
       _memberCache = memberCache ?? InMemoryCacheProvider(),
       _presenceCache = presenceCache ?? InMemoryCacheProvider(),
       _voiceStateCache = voiceStateCache ?? InMemoryCacheProvider();

  final String token;
  final Logger logger;
  final RestClient rest;

  final CacheProvider<Snowflake, Guild> _guildCache;
  final CacheProvider<Snowflake, Channel> _channelCache;
  final CacheProvider<Snowflake, User> _userCache;
  final CacheProvider<(Snowflake, Snowflake), GuildMember> _memberCache;

  /// Keyed by `(guildId, userId)`.
  final CacheProvider<(Snowflake, Snowflake), UserPresence> _presenceCache;

  /// Keyed by [VoiceState.connectionId]: one user can hold several
  /// connections at once.
  final CacheProvider<String, VoiceState> _voiceStateCache;

  /// Minimum gap between IDENTIFYs of shards sharing the same
  /// `session_start_limit.max_concurrency` bucket — see
  /// [GatewayShardManager].
  final Duration identifyPacing;

  /// Dispatch names the server drops before they reach this bot.
  ///
  /// Fluxer has no intent bitfield, so this is how a bot opts out of
  /// traffic it does not use. Names are upper-cased before being sent,
  /// and at most 256 are accepted. A `MESSAGE_CREATE` still arrives
  /// despite being listed if the message mentions this bot, or sets
  /// `mention_here` or `mention_everyone`.
  final Set<String> ignoredEvents;

  /// Presence published when each shard identifies.
  final Presence? initialPresence;

  /// Session behaviour flags sent with IDENTIFY.
  final SessionFlags sessionFlags;

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
  late final ThreadRestManager threads = ThreadRestManager(rest);
  late final GuildMemberRestManager members = GuildMemberRestManager(rest);
  late final GuildBanRestManager bans = GuildBanRestManager(rest);
  late final GuildEmojiRestManager emojis = GuildEmojiRestManager(rest);
  late final GuildStickerRestManager stickers = GuildStickerRestManager(rest);
  late final GuildRoleRestManager roles = GuildRoleRestManager(rest);
  late final InviteRestManager invites = InviteRestManager(rest);
  late final WebhookRestManager webhooks = WebhookRestManager(rest);
  late final UserRestManager users = UserRestManager(rest);
  late final AttachmentRestManager attachments = AttachmentRestManager(rest);
  late final GatewayRestManager _gatewayRest = GatewayRestManager(rest);

  final _eventsController = StreamController<GatewayEvent>.broadcast();
  final _stateController = StreamController<ShardStateChange>.broadcast();
  StreamSubscription<GatewayEvent>? _eventsSubscription;
  StreamSubscription<ShardStateChange>? _stateSubscription;
  GatewayShardManager? _shardManager;
  Snowflake? _selfId;

  /// This bot's own user id, populated once READY has come through —
  /// `null` before then. Lets command handlers tell their own actions
  /// (e.g. a reaction added via [MessageRestManager.addReaction] to set
  /// up pagination controls) apart from a real user's.
  Snowflake? get selfId => _selfId;

  /// Every gateway dispatch event, from every shard. Empty until [login]
  /// has been called and a READY/RESUMED has come through — see the
  /// `onXyz` streams below for narrowed, more convenient alternatives.
  Stream<GatewayEvent> get events => _eventsController.stream;

  /// Per-shard connection state transitions — see [ShardStateChange].
  Stream<ShardStateChange> get connectionStateChanges =>
      _stateController.stream;

  // Stream has no whereType (that's an Iterable method) — filter+cast by
  // hand, once here rather than in every getter below.
  Stream<T> _narrow<T extends GatewayEvent>() =>
      events.where((e) => e is T).cast<T>();

  Stream<ReadyEvent> get onReady => _narrow();
  Stream<ResumedEvent> get onResumed => _narrow();
  Stream<SessionsReplaceEvent> get onSessionsReplace => _narrow();

  Stream<MessageCreateEvent> get onMessageCreate => _narrow();
  Stream<MessageUpdateEvent> get onMessageUpdate => _narrow();
  Stream<MessageDeleteEvent> get onMessageDelete => _narrow();
  Stream<MessageReactionAddEvent> get onMessageReactionAdd => _narrow();
  Stream<MessageReactionRemoveEvent> get onMessageReactionRemove => _narrow();
  Stream<TypingStartEvent> get onTypingStart => _narrow();

  Stream<GuildCreateEvent> get onGuildCreate => _narrow();
  Stream<GuildSyncEvent> get onGuildSync => _narrow();
  Stream<GuildUpdateEvent> get onGuildUpdate => _narrow();
  Stream<GuildDeleteEvent> get onGuildDelete => _narrow();
  Stream<GuildRoleCreateEvent> get onGuildRoleCreate => _narrow();
  Stream<GuildRoleUpdateEvent> get onGuildRoleUpdate => _narrow();
  Stream<GuildRoleDeleteEvent> get onGuildRoleDelete => _narrow();
  Stream<GuildRoleUpdateBulkEvent> get onGuildRoleUpdateBulk => _narrow();
  Stream<GuildMemberAddEvent> get onGuildMemberAdd => _narrow();
  Stream<GuildMemberUpdateEvent> get onGuildMemberUpdate => _narrow();
  Stream<GuildMemberRemoveEvent> get onGuildMemberRemove => _narrow();
  Stream<GuildBanAddEvent> get onGuildBanAdd => _narrow();
  Stream<GuildBanRemoveEvent> get onGuildBanRemove => _narrow();
  Stream<GuildMembersChunkEvent> get onGuildMembersChunk => _narrow();
  Stream<RateLimitedEvent> get onRateLimited => _narrow();
  Stream<UserUpdateEvent> get onUserUpdate => _narrow();

  Stream<PresenceUpdateEvent> get onPresenceUpdate => _narrow();
  Stream<PresenceUpdateBulkEvent> get onPresenceUpdateBulk => _narrow();
  Stream<GuildMemberListUpdateEvent> get onGuildMemberListUpdate => _narrow();
  Stream<ThreadMemberListUpdateEvent> get onThreadMemberListUpdate => _narrow();
  Stream<GuildCountsUpdateEvent> get onGuildCountsUpdate => _narrow();
  Stream<ChannelMemberCountsUpdateEvent> get onChannelMemberCountsUpdate =>
      _narrow();
  Stream<ForumUnreadsEvent> get onForumUnreads => _narrow();
  Stream<VoiceStateUpdateEvent> get onVoiceStateUpdate => _narrow();

  Stream<ChannelCreateEvent> get onChannelCreate => _narrow();
  Stream<ChannelUpdateEvent> get onChannelUpdate => _narrow();
  Stream<ChannelDeleteEvent> get onChannelDelete => _narrow();
  Stream<ChannelUpdateBulkEvent> get onChannelUpdateBulk => _narrow();
  Stream<ChannelPinsUpdateEvent> get onChannelPinsUpdate => _narrow();

  Stream<ThreadCreateEvent> get onThreadCreate => _narrow();
  Stream<ThreadUpdateEvent> get onThreadUpdate => _narrow();
  Stream<ThreadDeleteEvent> get onThreadDelete => _narrow();
  Stream<ThreadListSyncEvent> get onThreadListSync => _narrow();
  Stream<ThreadMemberUpdateEvent> get onThreadMemberUpdate => _narrow();
  Stream<ThreadMembersUpdateEvent> get onThreadMembersUpdate => _narrow();

  Stream<MessageDeleteBulkEvent> get onMessageDeleteBulk => _narrow();
  Stream<MessageReactionRemoveAllEvent> get onMessageReactionRemoveAll =>
      _narrow();
  Stream<MessageReactionRemoveEmojiEvent> get onMessageReactionRemoveEmoji =>
      _narrow();

  Stream<GuildEmojisUpdateEvent> get onGuildEmojisUpdate => _narrow();
  Stream<GuildStickersUpdateEvent> get onGuildStickersUpdate => _narrow();
  Stream<GuildAuditLogEntryCreateEvent> get onGuildAuditLogEntryCreate =>
      _narrow();

  Stream<WebhooksUpdateEvent> get onWebhooksUpdate => _narrow();
  Stream<InviteCreateEvent> get onInviteCreate => _narrow();
  Stream<InviteDeleteEvent> get onInviteDelete => _narrow();

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
      ignoredEvents: ignoredEvents,
      initialPresence: initialPresence,
      sessionFlags: sessionFlags,
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
  /// Thread events and [ChannelUpdateBulkEvent] carry whole channels, so
  /// those are cached directly.
  ///
  /// Deleting a channel deletes its threads without a `THREAD_DELETE` for
  /// each, so [ChannelDeleteEvent] also drops every cached thread whose
  /// parent it was.
  void _handleEvent(GatewayEvent event) {
    switch (event) {
      case ReadyEvent(:final user):
        _userCache.set(user.id, user);
        _selfId = user.id;
      case GuildCreateEvent(
        :final guild,
        :final threads,
        :final channels,
        :final members,
        :final voiceStates,
      ):
        _cacheGuildState(
          guild,
          [...channels, ...threads],
          members,
          voiceStates,
        );
      case GuildSyncEvent(
        :final guild,
        :final threads,
        :final channels,
        :final members,
        :final voiceStates,
      ):
        _cacheGuildState(
          guild,
          [...channels, ...threads],
          members,
          voiceStates,
        );
      case PresenceUpdateEvent(:final presence):
        if (presence.guildId case final guildId?) {
          _presenceCache.set((guildId, presence.user.id), presence);
        }
      case PresenceUpdateBulkEvent(:final guildId, :final presences):
        for (final presence in presences) {
          _presenceCache.set((guildId, presence.user.id), presence);
        }
      case GuildMemberListUpdateEvent(:final guildId, :final ops):
        for (final op in ops) {
          for (final item in op.items) {
            if (item case MemberListMemberItem(
              :final member,
              :final presence,
            )) {
              _memberCache.set((guildId, member.user.id), member);
              _userCache.set(member.user.id, member.user);
              _presenceCache.set((guildId, member.user.id), presence);
            }
          }
        }
      case VoiceStateUpdateEvent(:final state):
        _applyVoiceState(state);
      case GuildUpdateEvent(:final guild):
        _guildCache.set(guild.id, guild);
      case GuildDeleteEvent(:final guildId):
        _guildCache.remove(guildId);
        final gone = _voiceStateCache.values
            .where((v) => v.guildId == guildId)
            .map((v) => v.connectionId)
            .toList();
        for (final id in gone) {
          if (id != null) _voiceStateCache.remove(id);
        }
      case ChannelCreateEvent(:final channel):
        _channelCache.set(channel.id, channel);
      case ChannelUpdateEvent(:final channelId):
        _channelCache.remove(channelId);
      case ChannelDeleteEvent(:final channelId):
        _channelCache.remove(channelId);
        final orphans = _channelCache.values
            .whereType<ThreadChannel>()
            .where((t) => t.parentId == channelId)
            .map((t) => t.id)
            .toList();
        orphans.forEach(_channelCache.remove);
      case ChannelUpdateBulkEvent(:final channels):
        for (final channel in channels) {
          _channelCache.set(channel.id, channel);
        }
      case UserUpdateEvent(:final user):
        _userCache.set(user.id, user);
      case GuildMembersChunkEvent(
        :final guildId,
        :final members,
        :final presences,
      ):
        for (final member in members) {
          _memberCache.set((guildId, member.user.id), member);
          _userCache.set(member.user.id, member.user);
        }
        for (final presence in presences) {
          _presenceCache.set((guildId, presence.user.id), presence);
        }
      case ThreadCreateEvent(:final thread):
        _channelCache.set(thread.id, thread);
      case ThreadUpdateEvent(:final thread):
        _channelCache.set(thread.id, thread);
      case ThreadDeleteEvent(:final threadId):
        _channelCache.remove(threadId);
      case ThreadListSyncEvent(:final threads):
        for (final thread in threads) {
          _channelCache.set(thread.id, thread);
        }
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
      case GuildRoleUpdateBulkEvent():
      case RateLimitedEvent():
      case ThreadMemberListUpdateEvent():
      case GuildCountsUpdateEvent():
      case ChannelMemberCountsUpdateEvent():
      case ForumUnreadsEvent():
      case GuildBanAddEvent():
      case GuildBanRemoveEvent():
      case MessageDeleteBulkEvent():
      case MessageReactionRemoveAllEvent():
      case MessageReactionRemoveEmojiEvent():
      case ChannelPinsUpdateEvent():
      case GuildEmojisUpdateEvent():
      case GuildStickersUpdateEvent():
      case GuildAuditLogEntryCreateEvent():
      case WebhooksUpdateEvent():
      case InviteCreateEvent():
      case InviteDeleteEvent():
      case ThreadMemberUpdateEvent():
      case ThreadMembersUpdateEvent():
      case SessionsReplaceEvent():
      case UnknownDispatchEvent():
        break;
    }
    _eventsController.add(event);
  }

  void _cacheGuildState(
    Guild guild,
    List<Channel> channels,
    List<GuildMember> members,
    List<VoiceState> voiceStates,
  ) {
    _guildCache.set(guild.id, guild);
    for (final channel in channels) {
      _channelCache.set(channel.id, channel);
    }
    for (final member in members) {
      _memberCache.set((guild.id, member.user.id), member);
      _userCache.set(member.user.id, member.user);
    }
    // The guild's voice states are complete here, so anything cached for
    // it and absent from the list has ended.
    final stale = _voiceStateCache.values
        .where((v) => v.guildId == guild.id)
        .map((v) => v.connectionId)
        .toList();
    for (final id in stale) {
      if (id != null) _voiceStateCache.remove(id);
    }
    voiceStates.forEach(_applyVoiceState);
  }

  void _applyVoiceState(VoiceState state) {
    final connectionId = state.connectionId;
    if (connectionId == null) return;
    if (state.channelId == null) {
      _voiceStateCache.remove(connectionId);
    } else {
      _voiceStateCache.set(connectionId, state);
    }
  }

  /// [userId]'s last known presence in [guildId], or `null` if none has
  /// arrived.
  ///
  /// A bot learns presences only by asking: [subscribe] with
  /// [GuildSubscription.members], a member list subscription, or
  /// [queryMembers] with `presences: true`. A presence is not removed
  /// when the user goes offline; it is replaced by one whose status is
  /// [PresenceStatus.offline].
  UserPresence? presence(Snowflake guildId, Snowflake userId) =>
      _presenceCache.get((guildId, userId));

  /// The voice connections currently open in [guildId], one entry per
  /// connection.
  List<VoiceState> voiceStates(Snowflake guildId) => [
    for (final state in _voiceStateCache.values)
      if (state.guildId == guildId) state,
  ];

  /// [userId]'s cached [User], or `null` if it has not been seen yet.
  ///
  /// Cache-only and synchronous; [fetchUser] falls back to a REST call.
  User? user(Snowflake userId) => _userCache.get(userId);

  /// [userId]'s [User], from cache if present, otherwise fetched via
  /// [users] and cached for next time.
  Future<User> fetchUser(Snowflake userId) async {
    final cached = _userCache.get(userId);
    if (cached != null) return cached;
    final fetched = await users.fetch(userId);
    _userCache.set(userId, fetched);
    return fetched;
  }

  /// Replaces the presence every shard publishes.
  ///
  /// Rate limited to five commands per 20 seconds per shard, with no
  /// acknowledgement either way.
  void updatePresence(Presence presence) {
    for (final shard in shards) {
      shard.updatePresence(presence);
    }
  }

  /// Asks for members of [guildId] over the gateway.
  ///
  /// Answered asynchronously as `GUILD_MEMBERS_CHUNK` dispatches on
  /// [events], not as a return value; [queryMembers] collects the answer
  /// for you. Sent on the shard that owns the guild, which is
  /// `(guildId >> 22) % shardCount`.
  void requestGuildMembers(
    Snowflake guildId, {
    String query = '',
    int limit = 0,
    List<Snowflake> userIds = const [],
    bool presences = false,
    String? nonce,
  }) {
    _shardFor(guildId)?.requestGuildMembers(
      guildId,
      query: query,
      limit: limit,
      userIds: userIds,
      presences: presences,
      nonce: nonce,
    );
  }

  GatewayConnection? _shardFor(Snowflake guildId) {
    final all = shards;
    return all.isEmpty ? null : all[(guildId.value >> 22) % all.length];
  }

  GatewayConnection _requireShardFor(Snowflake guildId, String what) =>
      _shardFor(guildId) ??
      (throw StateError('$what needs a gateway session; call login().'));

  /// Sets this bot's Lazy Request subscription for [guildId].
  ///
  /// A bot needs none to receive ordinary guild traffic. What it adds:
  /// [GuildSubscription.members] delivers `PRESENCE_UPDATE` for those
  /// members, [GuildSubscription.memberListChannels] a live member list,
  /// [GuildSubscription.threadMemberLists] thread member lists, and
  /// [GuildSubscription.typing] switches typing events on or off for
  /// this guild alone. The server keeps the options for the session.
  void subscribe(Snowflake guildId, GuildSubscription subscription) {
    _requireShardFor(guildId, 'subscribe').lazyRequest({guildId: subscription});
  }

  /// Member and online counts for [guildIds], fetched over the gateway.
  ///
  /// A guild that does not answer within 2 seconds is missing from the
  /// result, as is one this bot is not in. The online count covers the
  /// members sharing a channel with this bot, or the whole guild for a
  /// bot holding `administrator`.
  Future<List<GuildCounts>> guildCounts(
    List<Snowflake> guildIds, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final byShard = <GatewayConnection, List<Snowflake>>{};
    for (final id in guildIds) {
      byShard
          .putIfAbsent(_requireShardFor(id, 'guildCounts'), () => [])
          .add(id);
    }
    final results = await Future.wait([
      for (final MapEntry(key: shard, value: ids) in byShard.entries)
        _awaitNonced<GuildCountsUpdateEvent>(
          (nonce) => shard.requestGuildCounts(ids, nonce: nonce),
          (event) => event.nonce,
          timeout,
        ),
    ]);
    return [for (final event in results) ...event.counts];
  }

  /// Member and online counts for up to 25 channels of [guildId]. A
  /// channel this bot cannot view, or lacks `viewChannelMembers` in, is
  /// missing from the result.
  Future<List<ChannelMemberCounts>> channelMemberCounts(
    Snowflake guildId,
    List<Snowflake> channelIds, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final shard = _requireShardFor(guildId, 'channelMemberCounts');
    final event = await _awaitNonced<ChannelMemberCountsUpdateEvent>(
      (nonce) =>
          shard.requestChannelMemberCounts(guildId, channelIds, nonce: nonce),
      (event) => event.nonce,
      timeout,
    );
    return event.counts;
  }

  /// Unread counts for up to 40 posts in the forum or media channel
  /// [channelId]. A post given an acknowledged message reports how many
  /// came after it, capped at 25; one given none reports
  /// [ForumUnread.missing].
  ///
  /// The command carries no nonce, so the answer is matched by channel;
  /// overlapping calls for the same channel may receive each other's.
  Future<List<ForumUnread>> forumUnreads(
    Snowflake guildId,
    Snowflake channelId,
    List<ForumUnreadRequest> posts, {
    Duration timeout = const Duration(seconds: 12),
  }) async {
    final shard = _requireShardFor(guildId, 'forumUnreads');
    final answer = onForumUnreads
        .firstWhere((e) => e.channelId == channelId)
        .timeout(timeout);
    shard.requestForumUnreads(guildId, channelId, posts);
    return (await answer).threads;
  }

  Future<E> _awaitNonced<E extends GatewayEvent>(
    void Function(String nonce) send,
    String? Function(E event) nonceOf,
    Duration timeout,
  ) {
    final nonce = 'q${_nextNonce++}';
    final answer = _narrow<E>()
        .firstWhere((event) => nonceOf(event) == nonce)
        .timeout(timeout);
    send(nonce);
    return answer;
  }

  /// Requests members of [guildId] over the gateway and collects every
  /// `GUILD_MEMBERS_CHUNK` of the answer.
  ///
  /// With no [query] and a [limit] of 0 this is the full member list,
  /// which a bot may request once per guild every 30 seconds; a request
  /// inside that window throws [FluxerGatewayRateLimitException] with the
  /// time remaining. A non-empty [query] matches a display-name prefix
  /// and defaults to 25 results; [userIds] selects up to 100 members
  /// directly and ignores both. [presences] adds the online members'
  /// presences. Members received are also cached, see [member].
  ///
  /// The server abandons a request after 10 seconds without a word, so
  /// a [timeout] shorter than that can give up on a slow answer, and one
  /// longer only delays the [TimeoutException].
  Future<({List<GuildMember> members, List<UserPresence> presences})>
  queryMembers(
    Snowflake guildId, {
    String query = '',
    int limit = 0,
    List<Snowflake> userIds = const [],
    bool presences = false,
    Duration timeout = const Duration(seconds: 12),
  }) async {
    if (shards.isEmpty) {
      throw StateError('queryMembers needs a gateway session; call login().');
    }
    // The server discards these silently, which would surface only as a
    // timeout.
    RangeError.checkValueInInterval(limit, 0, 100, 'limit');
    if (userIds.length > 100) {
      throw ArgumentError.value(userIds.length, 'userIds', 'at most 100');
    }

    final nonce = 'q${_nextNonce++}';
    final members = <GuildMember>[];
    final presenceList = <UserPresence>[];
    final done = Completer<void>();
    var chunks = 0;
    final subscription = events.listen((event) {
      switch (event) {
        case GuildMembersChunkEvent(nonce: final n) when n == nonce:
          members.addAll(event.members);
          presenceList.addAll(event.presences);
          if (++chunks >= event.chunkCount && !done.isCompleted) {
            done.complete();
          }
        case RateLimitedEvent(nonce: final n) when n == nonce:
          if (!done.isCompleted) {
            done.completeError(
              FluxerGatewayRateLimitException(
                'Request Guild Members refused for guild $guildId',
                opcode: event.opcode,
                retryAfter: event.retryAfter,
              ),
            );
          }
        default:
      }
    });
    try {
      requestGuildMembers(
        guildId,
        query: query,
        limit: limit,
        userIds: userIds,
        presences: presences,
        nonce: nonce,
      );
      await done.future.timeout(timeout);
      return (
        members: List<GuildMember>.unmodifiable(members),
        presences: List<UserPresence>.unmodifiable(presenceList),
      );
    } finally {
      await subscription.cancel();
    }
  }

  int _nextNonce = 0;

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
