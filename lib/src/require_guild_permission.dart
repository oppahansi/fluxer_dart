import 'package:fluxer_dart_core/fluxer_dart_core.dart';
import 'package:fluxer_dart_rest/fluxer_dart_rest.dart';

import 'bot.dart';
import 'command_router.dart';

/// A [CommandMiddleware] that blocks a command unless the invoking member
/// has [flag] at the guild level, replying with why when it doesn't.
///
/// Guild-level only — [effectiveGuildPermissions] doesn't merge in
/// channel permission overwrites, so a member denied [flag] specifically
/// in this channel via an overwrite still passes this check. Fixing that
/// needs `PermissionOverwrite` resolution, which nothing in this
/// ecosystem reads back from the server yet (see `ChannelRestManager`'s
/// own note on why it's send-only so far).
///
/// Resolves the guild, member, and role list fresh on every call —
/// `guilds`/`members` are cache-aside via [Bot], but role lists aren't
/// cached anywhere yet, so this always hits `GET /guilds/{id}/roles`.
/// Fine for a demo bot; a bot handling real command volume would want to
/// cache the role list itself.
CommandMiddleware requireGuildPermission(PermissionFlag flag) {
  return (context) async {
    final message = context.message;
    final channel = await context.bot.channel(message.channelId);
    final guildId = channel.guildId;
    if (guildId == null) {
      await context.reply(
        MessageBuilder(content: 'This command only works in a guild channel.'),
      );
      return false;
    }

    final guild = await context.bot.guild(guildId);
    final member = await context.bot.member(guildId, message.author.id);
    final roles = await context.bot.roles.list(guildId);
    final permissions = effectiveGuildPermissions(
      member: member,
      guildId: guildId,
      guildOwnerId: guild.ownerId,
      roles: roles,
    );

    if (!permissions.has(flag)) {
      await context.reply(
        MessageBuilder(
          content: 'You need the `${flag.name}` permission to do that.',
        ),
      );
      return false;
    }
    return true;
  };
}
