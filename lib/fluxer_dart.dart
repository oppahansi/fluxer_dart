/// A bot framework for Fluxer: the [Bot] facade over fluxer_dart_gateway and
/// fluxer_dart_rest, re-exporting everything a bot author needs from the rest
/// of the ecosystem.
library;

// Full re-exports, not curated `show` lists: a curated list has to be kept
// in sync with every type a public `Bot` field or method exposes (e.g.
// RestClient), and the lower-level types this pulls in alongside the ones
// bot authors typically reach for (GatewayOpcode, HeartbeatManager,
// HttpTransport, ...) are exactly what a power user customizing `Bot`'s
// `gatewayConnectionFactory`/`restClient` injection points needs anyway.
export 'package:fluxer_dart_core/fluxer_dart_core.dart';
export 'package:fluxer_dart_gateway/fluxer_dart_gateway.dart';
export 'package:fluxer_dart_rest/fluxer_dart_rest.dart';
export 'package:fluxer_dart_utils/fluxer_dart_utils.dart';

export 'src/bot.dart';
export 'src/command_router.dart';
