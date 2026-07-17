# Troubleshooting

Use the detector for diagnosis. Do not troubleshoot first in trusted-answer or gatekeeper mode.

```zsh
export FACETIME_PICKER_IDENTITY_FILE="$PWD/config/trusted-callers.local.json"
zsh "./Build and Run Detector.command"
```

Default logs are designed to be shareable, but review them before posting. Logs produced with `--log-caller-text` can contain personal data and should not be shared publicly.

## Startup errors

| Message | Meaning | Resolution |
|---|---|---|
| `Configure exactly one trusted-caller source before running` | Neither source is configured, or both file and URL variables are set. | Set exactly one of `FACETIME_PICKER_IDENTITY_FILE` or `FACETIME_PICKER_IDENTITY_URL`. Use `unset` on the other variable. |
| `FACETIME_PICKER_IDENTITY_URL must use HTTPS` | The launcher found a non-HTTPS URL. | Use HTTPS in production or configure a local JSON file for offline development. |
| `Usage: FaceTimePicker ...` | A command-line option is missing, misspelled, or outside its accepted range. | Use the launcher scripts or review the option table in the README. |
| `Refusing to enable call actions without the launcher's explicit confirmation` | The binary was invoked directly in an action mode without `--confirmed-enable`. | Use the trusted-answer or gatekeeper launcher. Do not bypass the launcher casually. |
| `Accessibility permission is missing` | The current executable is not a trusted Accessibility client. | Add and enable `build/FaceTimePicker` under **System Settings → Privacy & Security → Accessibility**, then run again. |
| `Trusted-caller source failed: ...` | The initial file or HTTPS load failed. | Use the detailed identity-source error table below. Monitoring does not start until the source succeeds. |
| `FaceTime could not be located` | macOS could not resolve the FaceTime application. | Confirm FaceTime exists on the Mac and is not restricted or removed. |
| `Notification Center process was not found` | The process that exposes the compact call surface was not found within the startup timeout. | Confirm the desktop session is active, open Notification Center once, and rerun. Logging out and back in can restore a missing Notification Center process. |
| `Could not create Notification Center AX observer` | macOS rejected observer creation. | Recheck Accessibility permission, stop duplicate instances, and restart the desktop session if needed. |

### Accessibility permission does not stick

The current build is an ad-hoc-signed executable rather than a stable notarized app bundle. Rebuilding, moving, or replacing the executable can cause macOS to treat it as a different Accessibility client.

Try:

1. Stop FaceTime Picker.
2. Remove the old `FaceTimePicker` entry from Accessibility settings.
3. Run `zsh ./build.sh`.
4. Add the new `build/FaceTimePicker` executable.
5. Enable it and rerun the detector.

Apple's Accessibility prompt is asynchronous. The launch that opens System Settings can still exit; grant access and run again.

## Identity-source errors

| Error text | Meaning | Resolution |
|---|---|---|
| `Configure FACETIME_PICKER_IDENTITY_URL or FACETIME_PICKER_IDENTITY_FILE` | No identity source is configured. | Export one source variable. |
| `Configure exactly one identity source: URL or file, not both` | Both sources are configured. | `unset` the source you are not using. |
| `The configured identity URL is invalid` | URL parsing failed or the URL has no host. | Use a complete URL such as `https://service.example/trusted-callers`. |
| `The identity URL must use HTTPS` | The URL uses HTTP or another scheme. | Use HTTPS or local JSON. |
| `Invalid header mapping` | An item in `FACETIME_PICKER_HEADER_ENVS` is not `Header-Name=ENVIRONMENT_VARIABLE`. | Fix commas, equals signs, and header names. |
| `The required header environment variable ... is not set` | A mapped secret variable is missing or empty. | Export the named environment variable in the same shell before launching. |
| `The header value loaded from ... is invalid` | The header value contains a carriage return or line feed. | Replace it with a single-line value. |
| `The identity JSON file could not be read` | The path is wrong, unreadable, or points to a missing file. | Run `ls -l "$FACETIME_PICKER_IDENTITY_FILE"` and verify permissions. |
| `The identity response exceeded the 256 KB safety limit` | Provider response is too large. | Return only enabled trusted-caller fields and reduce the record count or payload metadata. |
| `The identity endpoint returned HTTP ...` | The endpoint returned a status other than `200`. | Test the endpoint with `curl`; verify authentication, path, and provider logs. |
| `The identity response did not match the documented JSON contract` | JSON shape or field types are invalid. | Compare the response with `docs/IDENTITY_API.md` and `openapi/trusted-callers.yaml`. |
| `Unsupported identity schema version ...` | Provider returned a version other than `1`. | Return `schemaVersion: 1`. |
| `The identity response contained an invalid phone number` | An enabled number has fewer than 7 or more than 15 digits after normalization. | Correct or disable the record. One invalid enabled record rejects the full snapshot. |
| `The identity response contained no enabled trusted callers` | The effective allowlist is empty. | Return at least one enabled valid caller. Review the empty-list caveat in the identity API documentation. |
| `The identity endpoint request timed out` | No complete response arrived before the configured deadline. | Check provider latency and network access; adjust `FACETIME_PICKER_REQUEST_TIMEOUT_SECONDS` up to 30 seconds only if necessary. |
| `The identity endpoint request failed` | DNS, TLS, connection, redirect, or other transport failure. | Test from the same Mac with `curl -v` and inspect provider/TLS configuration. |

## Verify a local JSON file

```zsh
ls -l "$FACETIME_PICKER_IDENTITY_FILE"
python3 -m json.tool "$FACETIME_PICKER_IDENTITY_FILE"
```

Confirm the file is the ignored `config/trusted-callers.local.json`, not the committed example file.

## Verify an HTTPS endpoint

```zsh
curl --fail-with-body \
  --silent \
  --show-error \
  --header "Accept: application/json" \
  --header "Authorization: Bearer replace-at-runtime" \
  "$FACETIME_PICKER_IDENTITY_URL" | python3 -m json.tool
```

Use the same header names and values configured through `FACETIME_PICKER_HEADER_ENVS`.

## Contacts and caller matching

### Raw number matches, saved name does not

Likely causes:

- Contacts permission is denied or restricted.
- Limited Contacts access does not include the trusted contact.
- The number stored in Contacts does not normalize to the provider number.
- The displayed name is shared by multiple local contacts.
- FaceTime is displaying an alias not present as the contact's full name or nickname.

Check the startup counts:

```text
matchingContactCount=...
uniqueAliasCount=...
ambiguousAliasCount=...
```

A configured number can still match directly even when `matchingContactCount=0`. Saved-name matching requires a resolved unique alias.

### A trusted contact is reported as ambiguous

The same normalized full name or nickname exists on more than one local contact. Rename the contacts so the trusted contact has a unique displayed alias, or rely on raw-number display. Ambiguous aliases are intentionally not trusted.

### Contacts access was changed while the process was running

Restart FaceTime Picker. It does not subscribe directly to `CNContactStoreDidChange`. A normal identity refresh re-resolves Contacts, but restarting is the clearest way to test a permission or contact edit immediately.

## Detector sees nothing during a call

1. Confirm startup reached `FOCUSED WINDOW POLL READY` and `READ-ONLY DETECTOR ENABLED`.
2. Confirm the incoming call appears as the compact call surface on the same logged-in desktop session.
3. Keep FaceTime Picker running in the foreground terminal.
4. Verify Accessibility permission for the current rebuilt executable.
5. Try both a video and audio FaceTime call.
6. Expand Notification Center once and test again.
7. Record the macOS version, FaceTime behavior, and privacy-safe detector logs.

The project relies on undocumented Accessibility details. A macOS update can change roles, subroles, labels, or containment enough to require code changes; documentation alone cannot guarantee compatibility.

## `CALL CANDIDATE` but no `CALL DETECTED`

A candidate did not yet contain all strong incoming-call evidence. The log's `missing=` field identifies absent evidence such as:

- `facetime`
- `container`
- `answer`
- `decline`
- `caller`

Repeated candidates missing the same field are useful when reporting a macOS compatibility problem. Do not enable raw caller text unless necessary, and redact it before sharing.

## Wrong action or duplicate action

Stop the process immediately with Control+C.

Do not restart gatekeeper mode until the scenario has been reproduced in detector mode and documented in [Manual testing](MANUAL_TESTING.md).

The monitor fingerprints active calls and applies an action cooldown, but undocumented Accessibility events may still change across macOS releases. Include the timing and action fields from default logs in a bug report.

## Phase launcher is locked

### Trusted answer is locked

Complete detector testing, then run:

```zsh
zsh "./Mark Phase 1 Proven.command"
```

### Full gatekeeper is locked

Complete trusted-answer testing, then run:

```zsh
zsh "./Mark Phase 2 Proven.command"
```

The marker files are ignored by Git and local to the checkout.

Reset them with:

```zsh
rm -f .phase1-proven .phase2-proven
```

## Refresh failures

### `IDENTITY REFRESH FAILED`

The previous valid snapshot is still active. The log includes the snapshot age as `staleSeconds`.

Restore the source before the effective stale deadline. The effective deadline is never shorter than the refresh interval.

### `IDENTITY CACHE EXPIRED`

The stale deadline was exceeded. FaceTime Picker has cleared the trusted identity index and trusts nobody until a refresh succeeds.

In trusted-answer mode, calls remain ringing. In gatekeeper mode, human-readable non-matches are declined and missing identity follows the 900 ms grace path.

### Provider returned an empty list to revoke everyone

An empty effective allowlist is rejected as a failed refresh. A previous snapshot can remain active until the stale deadline. Stop the process for immediate local revocation, or design a provider-side operational process that accounts for this behavior.

## CI passes but FaceTime behavior fails

This is possible and expected. CI validates:

- core identity and decision tests
- Swift compilation on macOS
- basic hardcoded-number regression scans

CI cannot create an incoming FaceTime call or inspect the live Notification Center hierarchy. Complete the manual test matrix on the target machine.

## Information to include in a bug report

- commit SHA
- Mac model and architecture
- exact macOS version
- FaceTime audio or video
- detector/trusted-answer/gatekeeper mode
- local JSON or HTTPS source
- Contacts authorization state
- whether the caller displayed a number or saved name
- expected result and actual result
- privacy-safe logs around the event
- confirmation that logs do not contain credentials or personal caller text
