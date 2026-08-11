/// A bot framework for Fluxer: the [Bot] facade over fluxer_gateway and
/// fluxer_rest, re-exporting everything a bot author needs from the rest
/// of the ecosystem.
library;

export 'package:fluxer_core/fluxer_core.dart';
export 'package:fluxer_gateway/fluxer_gateway.dart'
    show
        Closed,
        Connected,
        Connecting,
        Disconnected,
        GatewayConnection,
        GatewayConnectionState,
        GatewayEvent,
        GuildCreateEvent,
        Identifying,
        MessageCreateEvent,
        ReadyEvent,
        Reconnecting,
        ResumedEvent,
        Resuming,
        UnknownDispatchEvent;
export 'package:fluxer_rest/fluxer_rest.dart'
    show
        ChannelRestManager,
        GuildBanRestManager,
        GuildEmojiRestManager,
        GuildMemberRestManager,
        GuildRestManager,
        GuildRoleRestManager,
        GuildStickerRestManager,
        InviteRestManager,
        MessageBuilder,
        MessageRestManager,
        WebhookRestManager;
export 'package:fluxer_utils/fluxer_utils.dart'
    show LogLevel, Logger, NoopLogger, PrintLogger;

export 'src/bot.dart';
