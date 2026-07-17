# Contributing

FaceTime Picker automates sensitive call controls through undocumented macOS Accessibility behavior. Contributions should preserve the phased safety model, privacy defaults, and fail-closed identity rules.

## Development requirements

- A Mac running macOS 14.4 or later for native build and manual FaceTime testing.
- Xcode Command Line Tools with Swift 6 support.
- FaceTime.
- Accessibility permission for the locally built executable when testing the monitor.
- Contacts permission when testing saved-name matching.

Core identity tests can be compiled independently, but real call behavior requires macOS, FaceTime, and a logged-in graphical session.

## Set up a local checkout

```zsh
git clone https://github.com/tecxbro/FaceTime-picker.git
cd FaceTime-picker

cp config/trusted-callers.example.json \
  config/trusted-callers.local.json

export FACETIME_PICKER_IDENTITY_FILE="$PWD/config/trusted-callers.local.json"
```

Replace the example value only in the ignored local file.

## Before making changes

Read:

- [Architecture](docs/ARCHITECTURE.md)
- [Identity API](docs/IDENTITY_API.md)
- [Security model](docs/SECURITY_MODEL.md)
- [Manual testing](docs/MANUAL_TESTING.md)

Do not start development in gatekeeper mode.

## Build and test

Run before opening a pull request:

```zsh
zsh "./Validate Core Logic.command"
zsh ./build.sh
```

For changes that can affect call detection, identity, Contacts, timing, or actions, also complete the relevant manual test scenarios in `docs/MANUAL_TESTING.md`.

A green CI run does not prove real FaceTime behavior.

## Repository structure

- `Sources/` — native Swift implementation
- `Tests/` — standalone core regression tests
- `Resources/` — embedded executable metadata
- `docs/` — architecture, operation, testing, and security documentation
- `examples/` — provider adapters and deployment guides
- `openapi/` — machine-readable identity contract
- `config/` — committed example configuration only
- root `.command` files — guarded build, test, and rollout launchers

## Security invariants

A contribution must not:

- commit a real phone number, contact name, endpoint URL, token, API key, or database credential
- add a hardcoded trusted caller to Swift or launcher scripts
- accept identity-source secrets as command-line arguments
- log request headers, endpoint URLs, allowlist values, or raw caller text by default
- give the macOS process unrestricted database credentials
- treat an ambiguous Contacts alias as trusted
- treat an internal Accessibility label as human caller identity
- bypass the 900 ms grace path for missing/generic identity without explicit security review
- remove action-mode confirmation or proof-marker checks without explicit security review
- make trusted-answer mode decline callers
- perform network or database work in the incoming-call hot path
- silently continue after an invalid initial identity snapshot

If a proposed change intentionally alters one of these rules, explain the threat-model impact in the pull request and update the security and manual-testing documentation.

## Swift style

- Keep modules focused by responsibility.
- Prefer small testable functions for normalization and decision logic.
- Keep macOS-only framework code behind `#if os(macOS)`.
- Preserve Swift 6 compilation.
- Avoid force-unwrapping provider or Accessibility data.
- Bound Accessibility traversal and repeated work.
- Keep logging privacy-safe by default.
- Add comments for non-obvious safety constraints and undocumented platform assumptions, not for self-evident syntax.

The project does not currently require an external formatting tool. Match the existing two-space indentation and multiline style.

## Comments and documentation

Comments should explain **why**, especially when code exists to handle:

- undocumented Accessibility behavior
- identity ambiguity
- normalization compatibility
- action deduplication
- stale-cache rules
- secret-handling boundaries

Do not duplicate large operational instructions in source comments. Put user-facing procedures in `README.md` or `docs/` and link to them where useful.

Update documentation in the same pull request when behavior, configuration, limits, logs, provider contracts, or test expectations change.

## Provider examples

Provider examples must:

- keep administrative credentials server-side
- expose only the documented trusted-caller response
- authenticate the endpoint
- include deployment and `curl` verification instructions
- identify provider gateway settings that can block custom authentication
- use obvious placeholder data

When provider guidance changes, cite and follow the provider's current official documentation.

## Pull-request process

1. Create a focused branch from `main`.
2. Make the smallest coherent change.
3. Add or update core tests where pure logic changes.
4. Run core tests and the native build.
5. Complete manual tests for platform-sensitive changes.
6. Review the diff for private data.
7. Open a pull request with impact, risks, validation, and documentation changes.

## Pull-request checklist

Include this checklist in the pull-request description:

```markdown
- [ ] The change is focused and contains no unrelated files.
- [ ] No real phone numbers, names, endpoint URLs, or credentials are committed.
- [ ] `zsh "./Validate Core Logic.command"` passes.
- [ ] `zsh ./build.sh` passes on macOS.
- [ ] Relevant manual FaceTime scenarios were completed, or the PR explains why they are not applicable.
- [ ] Privacy-safe logging remains the default.
- [ ] Security invariants remain intact or the intentional change is documented.
- [ ] README, API, architecture, troubleshooting, security, and testing docs were updated where applicable.
```

## Bug reports

Use the repository issue templates. Include privacy-safe logs and exact environment details. Never post real caller identities or credentials.

Security vulnerabilities must follow [SECURITY.md](SECURITY.md) rather than a public bug report.

## License

By contributing, you agree that your contribution is licensed under the repository's MIT License.
