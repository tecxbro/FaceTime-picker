# FaceTime Picker

A native Swift 6 macOS helper that watches the compact incoming FaceTime call surface in Notification Center and applies a runtime allowlist:

- trusted caller → Answer
- explicit non-match → Decline in full-gatekeeper mode
- blank or generic identity → wait 900 ms, re-check, then fail closed

The repository contains **no real phone numbers, contact names, API URLs, or credentials**. Trusted numbers are loaded at runtime from a local JSON file or an HTTPS endpoint.

## Why the database integration is provider-agnostic

FaceTime Picker does not bundle database drivers. Instead, it consumes a tiny JSON contract over HTTPS. Any database—Supabase, Firebase, PostgreSQL, MySQL, MongoDB, Airtable, DynamoDB, or an internal system—can sit behind a small API or serverless function that returns that contract.

This is more portable and safer than connecting a desktop Accessibility tool directly to production databases.

See [docs/IDENTITY_API.md](docs/IDENTITY_API.md) and [openapi/trusted-callers.yaml](openapi/trusted-callers.yaml).

## Requirements

- macOS 14.4 or later
- Swift 6 / Xcode Command Line Tools
- FaceTime
- Accessibility permission for the compiled `build/FaceTimePicker` executable
- Contacts permission if FaceTime displays saved names rather than raw numbers

## Configure a trusted-caller source

### Local JSON for development

```zsh
cp config/trusted-callers.example.json config/trusted-callers.local.json
# Replace the example number only in the ignored local file.
export FACETIME_PICKER_IDENTITY_FILE="$PWD/config/trusted-callers.local.json"
```

### HTTPS endpoint for a database-backed deployment

```zsh
export FACETIME_PICKER_IDENTITY_URL="https://your-service.example/trusted-callers"
```

For arbitrary authentication headers, map header names to environment-variable names:

```zsh
export FACETIME_PICKER_HEADER_ENVS="Authorization=FACETIME_PICKER_AUTHORIZATION,apikey=FACETIME_PICKER_API_KEY"
export FACETIME_PICKER_AUTHORIZATION="Bearer replace-at-runtime"
export FACETIME_PICKER_API_KEY="replace-at-runtime"
```

Secrets are never accepted as command-line arguments and are never printed.

## Safe rollout

### Phase 1: detector

```zsh
zsh "./Build and Run Detector.command"
```

This mode never presses Answer or Decline.

### Phase 2: trusted answer

After testing the detector:

```zsh
zsh "./Mark Phase 1 Proven.command"
zsh "./Build and Run Trusted Answer.command"
```

This mode answers trusted callers and leaves all others ringing.

### Phase 3: full gatekeeper

After proving trusted auto-answer:

```zsh
zsh "./Mark Phase 2 Proven.command"
zsh "./Build and Run Gatekeeper.command"
```

This mode answers trusted callers and declines non-matches. A missing or internal Accessibility label is not treated as caller identity; it receives the 900 ms grace period.

## Privacy defaults

Normal logs contain only states such as `trusted`, `untrusted`, and `unverified`. They do not print the allowlist, contact aliases, endpoint URL, headers, credentials, or caller text.

For local debugging only, raw caller text can be enabled by invoking the binary with `--log-caller-text`. Do not use that flag in shared logs.

## Runtime refresh and failure behavior

The allowlist is cached in memory and refreshed every 300 seconds by default, or according to `cacheTTLSeconds` in the response. Set `--refresh-seconds N` to override it.

If refreshes fail, the last valid snapshot remains active only until `FACETIME_PICKER_MAX_STALE_SECONDS` (default: 900). After that, the allowlist is cleared and the program fails closed: no caller is trusted until the source recovers.

## Source layout

The native implementation is split into focused Swift modules for configuration, Contacts resolution, Accessibility traversal, call-card inspection, monitoring, refresh behavior, and startup. The build compiles every `Sources/*.swift` file.

## Validation

```zsh
zsh "./Validate Core Logic.command"
zsh ./build.sh
```

CI runs both on a GitHub-hosted macOS runner.

## Important limitations

- This relies on undocumented details of the macOS Accessibility representation of FaceTime notifications and must be re-tested after major macOS updates.
- Overall answer time includes time controlled by FaceTime/macOS before the call controls become accessible.
- English Answer/Decline labels are currently supported.
- A database is not contacted during each call; the in-memory snapshot is used so call handling remains fast.

## License

MIT. See [LICENSE](LICENSE).
