# FaceTime Picker

[![CI](https://github.com/tecxbro/FaceTime-picker/actions/workflows/ci.yml/badge.svg)](https://github.com/tecxbro/FaceTime-picker/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

> [!WARNING]
> FaceTime Picker is experimental macOS Accessibility automation. It depends on undocumented FaceTime and Notification Center UI details. Test in read-only mode after every macOS update before enabling automatic Answer or Decline actions.

FaceTime Picker watches the compact incoming FaceTime call interface, matches the displayed caller against a runtime allowlist, and can:

- **detect** calls without pressing anything;
- **answer trusted** callers while leaving everyone else ringing; or
- act as a **gatekeeper**, answering trusted callers and declining non-matches.

It is a source-first Swift 6 project for macOS. It builds a local executable at `build/FaceTimePicker`; it does **not** create a `.app` or install anything in `/Applications`.

## Requirements

- macOS 14.4 or later
- Xcode Command Line Tools with Swift 6
- FaceTime signed in and working
- Accessibility permission for `build/FaceTimePicker`
- Contacts permission when FaceTime displays saved names instead of raw numbers

## Quick start

```zsh
git clone https://github.com/tecxbro/FaceTime-picker.git
cd FaceTime-picker

cp config/trusted-callers.example.json config/trusted-callers.local.json
# Edit the copied file with test numbers only.
export FACETIME_PICKER_IDENTITY_FILE="$PWD/config/trusted-callers.local.json"

zsh ./test.sh
zsh ./build.sh
zsh ./run.sh detector
```

Start with `detector`. It is read-only and never presses Answer or Decline.

## First-run permissions

The executable needs Accessibility permission to read and press controls in Notification Center.

1. Run `zsh ./run.sh detector`.
2. Open **System Settings → Privacy & Security → Accessibility**.
3. Add and enable the exact file `build/FaceTimePicker` if macOS did not add it automatically.
4. Run detector mode again.

The Accessibility prompt is asynchronous, so the first launch may open System Settings and then exit. Rebuilding or moving the executable can require permission again.

Contacts access is used only to map a trusted phone number to the unique saved name or nickname that FaceTime displays. If access is denied, raw-number matching still works, but saved-name matching does not.

## Configure trusted callers

Configure exactly one source: a local JSON file or an HTTPS endpoint.

### Local JSON

```zsh
export FACETIME_PICKER_IDENTITY_FILE="$PWD/config/trusted-callers.local.json"
```

Canonical format:

```json
{
  "schemaVersion": 1,
  "trustedCallers": [
    {
      "id": "example",
      "phoneNumber": "+1 202 555 0147",
      "enabled": true
    }
  ],
  "cacheTTLSeconds": 300
}
```

Compatibility behavior:

- `snake_case` field names are accepted.
- A bare array of caller records is accepted.
- `enabled` defaults to `true` when omitted.
- Enabled numbers must contain 7–15 digits.
- Duplicate normalized numbers are ignored after the first.
- An empty enabled allowlist is rejected.

Never commit `config/trusted-callers.local.json`; it is ignored by Git.

### HTTPS endpoint

```zsh
export FACETIME_PICKER_IDENTITY_URL="https://your-service.example/trusted-callers"
```

The endpoint must:

- respond to `GET` with HTTP `200`;
- return the same JSON contract shown above;
- remain under 256 KB; and
- use HTTPS.

Map authentication headers to environment variables so secrets do not appear in command history:

```zsh
export FACETIME_PICKER_HEADER_ENVS="Authorization=FACETIME_PICKER_AUTH"
export FACETIME_PICKER_AUTH="Bearer replace-at-runtime"
```

Keep database administrator credentials on the server. The Mac should receive only a narrow endpoint token and the trusted-caller response.

## Run modes

```zsh
zsh ./run.sh detector
zsh ./run.sh answer-trusted
zsh ./run.sh gatekeeper
```

Action modes display a warning and require an exact typed confirmation every time they start. The launcher owns `--mode` and `--confirmed-enable` so extra arguments cannot bypass that confirmation.

Optional runtime arguments can follow the mode:

```zsh
zsh ./run.sh detector --refresh-seconds 120
zsh ./run.sh detector --max-stale-seconds 900
zsh ./run.sh detector --log-caller-text
```

`--log-caller-text` exposes caller information in terminal output. Use it only for local debugging and never post those logs without redaction.

## Decision behavior

| Displayed caller state | Detector | Answer trusted | Gatekeeper |
|---|---|---|---|
| Trusted raw number | Log | Answer | Answer |
| Unique saved alias belonging to a trusted number | Log | Answer | Answer |
| Explicit non-matching number or name | Log | Leave ringing | Decline |
| Alias shared by multiple Contacts | Log | Leave ringing | Decline |
| Missing or generic identity | Log | Leave ringing | Recheck for 900 ms, then decline if still unverified |
| Contacts unavailable | Raw-number matching only | Raw-number matching only | Raw-number matching only |

Aliases are trusted only when exactly one local contact owns that normalized name or nickname. This prevents a duplicated contact name from becoming an accidental allowlist match.

## Build and test

```zsh
zsh ./test.sh
zsh ./build.sh
```

`test.sh` compiles and runs the platform-independent identity/configuration tests. `build.sh` compiles all `Sources/*.swift`, embeds `Resources/Info.plist`, and ad-hoc signs the executable for local use.

GitHub Actions validates:

1. shell syntax;
2. core tests;
3. the native macOS build; and
4. a scan for legacy hardcoded-number patterns.

CI cannot place a real FaceTime call, grant macOS permissions, or verify the current undocumented Accessibility hierarchy. Those checks must be performed manually on the target Mac.

## Manual verification before action modes

Use test contacts and complete at least these scenarios in detector mode:

- trusted raw number;
- trusted saved name;
- untrusted number or saved name;
- duplicated/ambiguous saved name;
- Contacts denied;
- incoming FaceTime Audio and Video;
- invalid or unavailable identity source; and
- refresh failure followed by recovery.

Then test `answer-trusted` before testing `gatekeeper`. Stop immediately with Control+C if an unexpected control is pressed.

## Runtime refresh and failure behavior

The initial allowlist load must succeed before monitoring starts. The valid snapshot is then cached in memory, so no network request occurs while deciding an incoming call.

The default refresh interval is 300 seconds unless the response supplies `cacheTTLSeconds` or `--refresh-seconds` overrides it. TTL values are clamped to 30–86400 seconds.

After a refresh failure, the last valid snapshot remains active until the stale deadline. The effective stale duration is never shorter than the refresh interval. Once expired, the identity index is cleared and no caller is trusted until a refresh succeeds.

## Troubleshooting

**“Configure exactly one trusted-caller source”**  
Set either `FACETIME_PICKER_IDENTITY_FILE` or `FACETIME_PICKER_IDENTITY_URL`, not both.

**“Accessibility permission is missing”**  
Enable `build/FaceTimePicker` in System Settings, then rerun. Re-enable it after rebuilding if necessary.

**Trusted number works but saved name does not**  
Grant Contacts access and confirm the displayed contact contains the trusted number. A duplicated name or nickname intentionally fails closed.

**Identity source failed**  
For files, verify the path and JSON. For endpoints, verify HTTPS, HTTP 200, authentication headers, response size, schema version, and at least one enabled valid number.

**Detector sees only partial candidates**  
FaceTime or macOS may have changed its Accessibility tree. Do not enable action modes until the detector is verified again.

## Source map

| Path | Responsibility |
|---|---|
| `Sources/FaceTimePickerMain.swift` | Startup, permissions, initial identity load, monitor lifecycle |
| `Sources/CoreLogic.swift` | Number/name normalization and trust decisions |
| `Sources/TrustedCaller*.swift` | JSON contract and file/HTTPS loading |
| `Sources/ContactsResolver.swift` | Trusted-number to unique Contacts alias resolution |
| `Sources/CallInspection.swift` | Bounded Accessibility-tree inspection |
| `Sources/NotificationCenter*.swift` | Observer, polling fallback, call state, and control actions |
| `Sources/IdentityRefresh.swift` | Periodic refresh and stale-cache fail-closed behavior |
| `Tests/CoreLogicTests.swift` | Pure logic regression tests |
| `run.sh`, `build.sh`, `test.sh` | The only user-facing shell entry points |

## Privacy and limitations

Normal logs omit raw caller text, allowlist values, endpoint URLs, and header values. Do not commit real phone numbers, names, URLs, tokens, or local configuration files.

FaceTime Picker recognizes English Answer/Accept and Decline/Reject labels. Overall response time includes delays controlled by FaceTime and macOS. The project does not include a notarized installer, launch agent, or background service.

## License

MIT. See [LICENSE](LICENSE).
