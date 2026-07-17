# Security policy

FaceTime Picker uses macOS Accessibility permission and can press FaceTime Answer or Decline controls. Please report security problems privately whenever possible.

For the design assumptions, trust boundaries, privacy behavior, and fail-closed rules, see [docs/SECURITY_MODEL.md](docs/SECURITY_MODEL.md).

## Supported versions

This project is experimental and does not currently publish stable release branches.

Security fixes are applied to the current `main` branch. Older commits and forks may not receive updates.

## Report a vulnerability

Use GitHub's **Security → Report a vulnerability** flow for this repository when it is available. This creates a private vulnerability report visible to repository maintainers.

Do not open a public issue containing:

- working exploit instructions
- real phone numbers or caller identities
- authentication headers or credentials
- private endpoint URLs
- unredacted logs produced with `--log-caller-text`
- details that would let another person trigger unauthorized Answer or Decline actions

If private vulnerability reporting is not available, contact the repository owner through their GitHub profile to establish a private channel before sharing sensitive details. A public issue may be used only to say that you need to report a security concern; do not include the vulnerability itself.

## What to include

Provide as much of the following as is safe:

- affected commit SHA
- exact macOS version and build
- Mac architecture
- detector, trusted-answer, or gatekeeper mode
- local JSON or HTTPS source type
- Contacts and Accessibility authorization state
- clear reproduction steps using test data
- expected and actual behavior
- privacy-safe logs
- impact assessment
- suggested mitigation, when known

Replace all real phone numbers, names, endpoint URLs, tokens, keys, and provider identifiers with obvious placeholders.

## Response expectations

This is an independently maintained experimental project and does not promise a formal response-time SLA.

Maintainers should, on a best-effort basis:

1. acknowledge a complete private report
2. reproduce and assess the impact
3. coordinate a fix or mitigation
4. avoid publishing sensitive details before a fix is available
5. credit the reporter when requested and appropriate

## Security scope

Examples of in-scope concerns include:

- an untrusted or ambiguous caller being treated as trusted
- missing identity bypassing the intended grace path
- action modes starting without the required confirmation safeguards
- credentials, endpoint URLs, allowlist values, or caller text appearing in default logs
- provider-response parsing that expands trust unexpectedly
- stale-cache behavior that differs from the documented fail-closed model
- duplicate or delayed Accessibility actions affecting another call
- repository examples exposing server-side credentials to the macOS client

General reliability failures, unsupported localized labels, and macOS Accessibility changes may be filed as normal bugs when they do not create a security impact.

## Disclosure

Allow maintainers time to investigate and publish a fix before public disclosure. Coordinate the timing and content of any advisory or proof of concept through the private report.

Never include another person's caller information or live credentials in a disclosure.
