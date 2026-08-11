import 'dart:async';

import 'package:fluxer_core/fluxer_core.dart';
import 'package:fluxer_gateway/fluxer_gateway.dart';
import 'package:fluxer_rest/fluxer_rest.dart';

import 'bot.dart';

/// Everything a command handler needs: the triggering message, the parsed
/// command name and arguments, and the [Bot] to act through.
final class CommandContext {
  const CommandContext({
    required this.bot,
    required this.message,
    required this.commandName,
    required this.args,
  });

  final Bot bot;
  final Message message;

  /// The command name matched, without the router's prefix.
  final String commandName;

  /// [message.content] after the prefix and command name, split on
  /// whitespace. Empty if none were given.
  final List<String> args;

  /// Sends [builder] to the channel [message] was posted in.
  Future<Message> reply(MessageBuilder builder) => bot.reply(message, builder);
}

typedef CommandHandler = Future<void> Function(CommandContext context);

/// A step in a command's Chain of Responsibility: runs before the
/// handler, returning `false` to short-circuit (skip the handler and any
/// later middleware) or `true` to let the chain continue.
typedef CommandMiddleware = Future<bool> Function(CommandContext context);

/// Message-content command routing: fluent `.command()` registration
/// instead of decorators, since Dart has no lightweight runtime-decorator
/// story for that.
///
/// Attaches to [bot.onMessageCreate] as soon as it's constructed. Messages
/// from other bots are always ignored; a message that doesn't start with
/// [prefix], or whose command name isn't registered, is left alone (not
/// an error — most messages in a channel aren't commands at all).
final class CommandRouter {
  CommandRouter({required this.bot, required this.prefix}) {
    _subscription = bot.onMessageCreate.listen(_handle);
  }

  final Bot bot;
  final String prefix;

  final _commands = <String, (CommandHandler, List<CommandMiddleware>)>{};
  late final StreamSubscription<void> _subscription;

  /// Registers [handler] for [name], run after every middleware in
  /// [middleware] (in order) returns `true`. Returns `this` for chaining.
  CommandRouter command(
    String name,
    CommandHandler handler, {
    List<CommandMiddleware> middleware = const [],
  }) {
    _commands[name] = (handler, middleware);
    return this;
  }

  Future<void> _handle(MessageCreateEvent event) async {
    final message = event.message;
    if (message.author.bot) return;
    if (!message.content.startsWith(prefix)) return;

    final rest = message.content.substring(prefix.length);
    final parts = rest.split(RegExp(r'\s+')).where((s) => s.isNotEmpty);
    if (parts.isEmpty) return;

    final name = parts.first;
    final entry = _commands[name];
    if (entry == null) return;
    final (handler, middleware) = entry;

    final context = CommandContext(
      bot: bot,
      message: message,
      commandName: name,
      args: parts.skip(1).toList(),
    );
    for (final step in middleware) {
      if (!await step(context)) return;
    }
    await handler(context);
  }

  Future<void> dispose() => _subscription.cancel();
}

/// A [CommandMiddleware] that blocks a command from running again for the
/// same user within [duration] of their last use, silently (no reply) —
/// compose custom middleware instead if a cooldown notice is wanted.
CommandMiddleware cooldown(
  Duration duration, {
  DateTime Function() now = DateTime.now,
}) {
  final lastUsedAt = <Snowflake, DateTime>{};
  return (context) async {
    final userId = context.message.author.id;
    final last = lastUsedAt[userId];
    final currentTime = now();
    if (last != null && currentTime.difference(last) < duration) return false;
    lastUsedAt[userId] = currentTime;
    return true;
  };
}
