# Contributing to fluxer_dart

Thanks for considering a contribution. fluxer_dart is one of seven
repositories in the `fluxer_dart` ecosystem — a Dart bot framework for
[Fluxer](https://fluxer.app):

| Package | Purpose |
|---|---|
| [`fluxer_dart_utils`](https://github.com/oppahansi/fluxer_dart_utils) | generic building blocks |
| [`fluxer_dart_core`](https://github.com/oppahansi/fluxer_dart_core) | domain models |
| [`fluxer_dart_rest`](https://github.com/oppahansi/fluxer_dart_rest) | REST client |
| [`fluxer_dart_gateway`](https://github.com/oppahansi/fluxer_dart_gateway) | WebSocket gateway client |
| [`fluxer_dart_voice`](https://github.com/oppahansi/fluxer_dart_voice) | voice support |
| [`fluxer_dart`](https://github.com/oppahansi/fluxer_dart) | main framework — the `Bot` facade |
| [`fluxer_dart_bot`](https://github.com/oppahansi/fluxer_dart_bot) | example bot |

Depends on `fluxer_dart_core`, `fluxer_dart_rest`, `fluxer_dart_gateway`, and `fluxer_dart_utils`; depended on by `fluxer_dart_bot`. This is the package most bot authors interact with directly.

## Local development setup

The packages depend on each other via local `path:` entries in
`pubspec.yaml` during development, so clone the repos you need as
sibling directories (matching the names above) rather than in
isolation:

```sh
mkdir fluxer_dart_workspace && cd fluxer_dart_workspace
git clone https://github.com/oppahansi/fluxer_dart_utils.git
git clone https://github.com/oppahansi/fluxer_dart_core.git
git clone https://github.com/oppahansi/fluxer_dart_rest.git
git clone https://github.com/oppahansi/fluxer_dart_gateway.git
git clone https://github.com/oppahansi/fluxer_dart_voice.git
git clone https://github.com/oppahansi/fluxer_dart.git
git clone https://github.com/oppahansi/fluxer_dart_bot.git
```

Then, in fluxer_dart:

```sh
dart pub get
dart test
```

## Before opening a pull request

All three of these run in CI and must pass:

```sh
dart format --output=none --set-exit-if-changed .
dart analyze --fatal-infos
dart test
```

Add or update tests for any behavior change — this ecosystem uses
`package:test` + `package:mocktail` (no codegen step) to mock the
REST/gateway boundary, so tests don't need live network access.

## Verifying changes

Most of what this package does is compose `fluxer_dart_core`,
`fluxer_dart_rest`, and `fluxer_dart_gateway` — protocol-level
verification belongs in those repos' own PRs. For changes here (the
`Bot` facade, caching, `CommandRouter`), the useful check is usually
end-to-end: run a bot against a real (self-hosted) Fluxer instance and
confirm the behavior actually happens, not just that a mocked unit test
passes. `fluxer_dart_bot` is a convenient place to exercise a change
this way before opening the PR.

## Commit messages

Commits follow [scoped commits](https://scopedcommits.com) —
`<scope>: <description>`, not Conventional Commits' `type(scope):`
format. Keep the description in imperative mood ("add", not "added").

## Code style

- `package:lints/recommended.yaml` — nothing stricter is enforced beyond
  what `dart analyze --fatal-infos` already catches.
- Default to no comments; when one is warranted, it should explain *why*
  something non-obvious is true, not restate what the code already says.
- Small, focused PRs are easier to review than large ones — if a change
  naturally splits into independent pieces, prefer separate PRs.

## Pull request process

1. Fork the repo and branch off `main`.
2. Make your change, with tests.
3. Make sure the three checks above pass locally.
4. Open a PR against `main` — the template will prompt for what's
   relevant.
5. CI runs the same three checks; a maintainer will review from there.

## Code of Conduct

Participation in this project is governed by the
[Code of Conduct](CODE_OF_CONDUCT.md).

## Reporting security issues

Please don't open a public issue for a security vulnerability — see
[SECURITY.md](SECURITY.md) instead.

## Questions

Open a [discussion or issue](https://github.com/oppahansi/fluxer_dart/issues) —
there's no separate chat/forum for this project.
