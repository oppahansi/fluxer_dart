## Summary

<!-- What does this PR change, and why? -->

## Related issue

<!-- Closes #123, or "N/A" -->

## Type of change

- [ ] Bug fix
- [ ] New feature
- [ ] Breaking change
- [ ] Documentation
- [ ] Refactor / internal, no behavior change

## Checklist

- [ ] `dart format --output=none --set-exit-if-changed .` passes
- [ ] `dart analyze --fatal-infos` passes
- [ ] `dart test` passes
- [ ] Added/updated tests for the change
- [ ] If this touches anything that talks to Fluxer's actual API/gateway
      (payload shapes, endpoints, permission requirements, defaults):
      verified against the live OpenAPI spec and/or a real instance, not
      assumed from Discord parity or documentation alone — briefly note
      how below
- [ ] Updated the relevant README section(s), if behavior or scope
      changed

## How this was verified

<!--
For anything protocol-related: what did you actually check, and
against what (a self-hosted instance, api.fluxer.app, the OpenAPI spec,
Fluxer's own source)? "Should work" isn't verification — this ecosystem
has caught several real bugs specifically by checking against the live
platform instead of assuming.
-->
