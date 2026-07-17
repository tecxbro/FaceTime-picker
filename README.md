# FaceTime Picker

[![CI](https://github.com/tecxbro/FaceTime-picker/actions/workflows/ci.yml/badge.svg)](https://github.com/tecxbro/FaceTime-picker/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
![macOS 14.4+](https://img.shields.io/badge/macOS-14.4%2B-black)
![Swift 6](https://img.shields.io/badge/Swift-6-orange)

> [!WARNING]
> **Experimental macOS automation.** FaceTime Picker depends on undocumented Accessibility representations exposed by FaceTime and Notification Center. Re-test it after macOS or FaceTime updates before enabling automatic call actions.
>
> This is not an official Apple integration. The current build creates an ad-hoc-signed executable at `build/FaceTimePicker`; it does not create a `.app` bundle or install anything in `/Applications`.

FaceTime Picker is a native Swift 6 macOS helper that watches the compact incoming FaceTime call surface in Notification Center and applies a runtime trusted-caller allowlist.

It does not modify FaceTime, inject code into FaceTime, or connect the macOS process directly to a production database. Trusted numbers are loaded at runtime from either a local JSON file or an authenticated HTTPS endpoint.

The repository contains **no real phone numbers, contact names, API URLs, or credentials**.

## Call decision matrix

| Caller state | Detector | Trusted answer | Full gatekeeper |
|---|---|---|---|
| Trusted phone number | Log only | Answer | Answer |
| Unique saved Contacts alias belonging to a trusted number | Log only | Answer | Answer |
| Explicit non-matching number or human-readable name | Log only | Leave ringing | Decline immediately |
| Ambiguous Contacts alias | Log only | Leave ringing | Decline immediately |
| Missing, generic, or internal Accessibility identity | Log only | Leave ringing | Recheck for 900 ms, then decline if still unverified |
| Contacts access unavailable | Raw-number matching only | Raw-number matching only | Raw-number matching only |

An ambiguous alias means a trusted contact's displayed name or nickname is also owned by another local contact. FaceTime Picker does not trust that alias because it cannot identify one contact uniquely.

## Requirements

- macOS 14.4 or later
- Swift 6 and Xcode Command Line Tools
- FaceTime
- Accessibility permission for the compiled `build/FaceTimePicker` executable
- Contacts permission when FaceTime displays saved names instead of raw phone numbers

## Quick start with local JSON

```zsh
git clone https://github.com/tecxbro/FaceTime-picker.git
cd FaceTime-picker

cp config/trusted-callers.example.json \
  config/trusted-callers.local.json

# Edit only the ignored local file, then configure it for this shell.
export FACETIME_PICKER_IDENTITY_FILE="$PWD/config/trusted-callers.local.json"

zsh "./Validate Core Logic.command"
zsh ./build.sh
zsh "./Build and Run Detector.command"
```

The detector is read-only. It never presses Answer or Decline.

### First-run permissions

On the first run, macOS may request Accessibility and Contacts access.

1. When the Accessibility prompt appears, open **System Settings → Privacy & Security → Accessibility**.
2. Add the exact executable at `build/FaceTimePicker` if macOS did not add it automatically.
3. Enable the executable.
4. Run the detector again.

Apple's Accessibility prompt is asynchronous, so the first launch can still exit after opening System Settings. Grant access and rerun the command.

Contacts access is optional only when FaceTime exposes the caller's raw phone number. If FaceTime displays a saved name and Contacts access is denied or restricted, that saved-name caller cannot be verified.

### Expected detector startup

A healthy startup contains messages similar to:

```text
BUILD facetime-picker-v1-provider-agnostic
TRUSTED IDENTITIES LOADED ...
FOCUSED WINDOW POLL READY ...
IDENTITY REFRESH READY ...
READ-ONLY DETECTOR ENABLED ...
```

During an incoming call, the detector logs either `CALL DETECTED` or a partial `CALL CANDIDATE`. Default logs use privacy-safe states such as `trusted`, `untrusted`, `ambiguous`, and `unverified` rather than caller text.

## Why database integration is provider-neutral

FaceTime Picker does not bundle database drivers. Instead, it consumes a small JSON contract over HTTPS. Supabase, Firebase, PostgreSQL, MySQL, MongoDB, Airtable, DynamoDB, or an internal system can sit behind a narrow API or serverless function that returns the contract.

This is more portable and safer than giving a desktop Accessibility process unrestricted production-database credentials.

See:

- [Trusted-caller identity API](docs/IDENTITY_API.md)
- [OpenAPI contract](openapi/trusted-callers.yaml)
- [Supabase deployment example](examples/supabase/README.md)
- [Firebase deployment example](examples/firebase/README.md)

## Configure a trusted-caller source

Configure **exactly one** source. Setting both variables, or neither variable, causes startup to fail.

### Local JSON

```zsh
export FACETIME_PICKER_IDENTITY_FILE="$PWD/config/trusted-callers.local.json"
```

The path supports `~` expansion.

### HTTPS endpoint

```zsh
export FACETIME_PICKER_IDENTITY_URL="https://your-service.example/trusted-callers"
```

Production endpoints must use HTTPS. Plain HTTP is rejected; use a local JSON file for offline development.

For arbitrary authentication headers, map each header name to the name of an environment variable containing its value:

```zsh
export FACETIME_PICKER_HEADER_ENVS="Authorization=FACETIME_PICKER_AUTHORIZATION,apikey=FACETIME_PICKER_API_KEY"
export FACETIME_PICKER_AUTHORIZATION="Bearer replace-at-runtime"
export FACETIME_PICKER_API_KEY="replace-at-runtime"
```

Header values are never accepted as command-line arguments and are not printed in normal logs.

## Configuration reference

### Environment variables

| Variable | Required | Meaning |
|---|---:|---|
| `FACETIME_PICKER_IDENTITY_FILE` | One of file/URL | Local JSON allowlist path. Cannot be combined with the URL variable. |
| `FACETIME_PICKER_IDENTITY_URL` | One of file/URL | HTTPS identity endpoint. Cannot be combined with the file variable. |
| `FACETIME_PICKER_HEADER_ENVS` | No | Comma-separated `Header-Name=ENVIRONMENT_VARIABLE` mappings. |
| `FACETIME_PICKER_REQUEST_TIMEOUT_SECONDS` | No | HTTPS timeout. Default `8`; clamped to `1`–`30` seconds. |
| `FACETIME_PICKER_MAX_STALE_SECONDS` | No | Requested maximum age of the last successful snapshot. Default `900`; minimum `60`. The effective value is never shorter than the refresh interval. |

### Command-line options

The launcher scripts supply the action-mode flags. Direct invocation is mainly useful for diagnostics.

| Option | Meaning |
|---|---|
| `--mode detector` | Observe and log without pressing call controls. This is the default mode. |
| `--mode answer-trusted` | Answer trusted callers and leave other calls ringing. |
| `--mode gatekeeper` | Answer trusted callers and decline explicit non-matches. |
| `--confirmed-enable` | Required safety acknowledgement for action modes. Normally supplied only by the launcher scripts. |
| `--log-caller-text` | Include raw caller text in logs. Do not use in shared logs. |
| `--refresh-seconds N` | Override the response TTL. Accepted range: `30`–`86400` seconds. |
| `--max-stale-seconds N` | Override stale duration. Accepted range: `60`–`604800` seconds. |

## Safe rollout

Do not begin with gatekeeper mode. Use all three phases on the target Mac and macOS version.

### Phase 1: detector

```zsh
zsh "./Build and Run Detector.command"
```

Confirm that trusted, untrusted, ambiguous, and temporarily unverified calls are classified correctly. The detector must never press a control.

After completing the [manual Phase 1 tests](docs/MANUAL_TESTING.md):

```zsh
zsh "./Mark Phase 1 Proven.command"
```

This creates the ignored local marker `.phase1-proven`.

### Phase 2: trusted answer

```zsh
zsh "./Build and Run Trusted Answer.command"
```

The launcher requires `.phase1-proven`, warns that auto-answer exposes the camera and microphone, and requires the exact confirmation `ENABLE`.

This mode answers trusted callers and leaves all other callers ringing.

After completing the manual Phase 2 tests:

```zsh
zsh "./Mark Phase 2 Proven.command"
```

This creates the ignored local marker `.phase2-proven`.

### Phase 3: full gatekeeper

```zsh
zsh "./Build and Run Gatekeeper.command"
```

The launcher requires `.phase2-proven` and the exact confirmation `ENABLE GATEKEEPER`.

Full gatekeeper behavior:

- trusted number or unique trusted Contacts alias → answer immediately
- explicit human-readable non-match → decline immediately
- ambiguous Contacts alias → decline immediately
- missing or generic Accessibility identity → wait 900 ms, inspect again, then decline if still unverified

To reset the local rollout locks, stop the process and remove the marker files manually:

```zsh
rm -f .phase1-proven .phase2-proven
```

Removing a marker does not stop an already-running process. Press Control+C in the terminal that launched FaceTime Picker.

## What gets built

`build.sh` compiles every `Sources/*.swift` file into:

```text
build/FaceTimePicker
```

The executable embeds `Resources/Info.plist` and is ad-hoc signed with identifier `com.tecxbro.FaceTimePicker`. It is not a distributable notarized application bundle. Accessibility permission is attached to the compiled executable, so rebuilding or moving it may require re-enabling permission.

## Privacy defaults

Normal logs do not print:

- the allowlist
- resolved Contacts aliases
- the identity endpoint URL
- authentication header names or values
- raw caller text

For local debugging only, raw caller text can be enabled by invoking the binary with `--log-caller-text`. Treat those logs as sensitive.

## Runtime refresh and failure behavior

The first identity-source load must succeed before monitoring begins.

After startup, the allowlist is cached in memory. No database or network request occurs in the incoming-call decision path. The default refresh interval is 300 seconds, or the clamped `cacheTTLSeconds` supplied by the response. `--refresh-seconds` overrides the response value.

When a refresh fails, the last valid snapshot remains active until the effective stale deadline. The effective maximum stale duration is the larger of:

- `FACETIME_PICKER_MAX_STALE_SECONDS` or `--max-stale-seconds`
- the active refresh interval

After that deadline, the allowlist is cleared and no caller is trusted until a refresh succeeds.

An empty allowlist is rejected as an invalid snapshot. It does not immediately replace a previously valid snapshot with an empty one; the previous snapshot can remain active until the stale deadline.

## Validation

```zsh
zsh "./Validate Core Logic.command"
zsh ./build.sh
```

GitHub Actions runs the core tests, the native macOS build, and a regression scan for hardcoded-number patterns on a GitHub-hosted `macos-15` runner.

CI does **not** generate a real FaceTime call or validate:

- the current FaceTime/Notification Center Accessibility hierarchy
- macOS permission prompts
- real Answer or Decline button presses
- saved-name presentation on a particular machine
- behavior changes introduced by a macOS or FaceTime update

Complete [manual FaceTime testing](docs/MANUAL_TESTING.md) before enabling Phase 2 or Phase 3.

## Important limitations

- Incoming-call detection relies on undocumented macOS Accessibility details.
- English Answer, Accept, Decline, and Reject labels are currently recognized.
- Overall response time includes time controlled by FaceTime and macOS before controls become accessible.
- Contacts aliases are trusted only when the alias belongs to exactly one local contact.
- The program does not currently subscribe to live Contacts changes; refreshed identity snapshots re-resolve Contacts periodically.
- This repository is source-first and does not provide a notarized installer or background launch agent.

## Documentation

- [Architecture](docs/ARCHITECTURE.md)
- [Identity API contract](docs/IDENTITY_API.md)
- [Troubleshooting](docs/TROUBLESHOOTING.md)
- [Manual FaceTime testing](docs/MANUAL_TESTING.md)
- [Security model](docs/SECURITY_MODEL.md)
- [Security reporting policy](SECURITY.md)
- [Contributing](CONTRIBUTING.md)

## License

MIT. See [LICENSE](LICENSE).
