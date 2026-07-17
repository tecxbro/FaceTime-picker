# Manual FaceTime testing

GitHub Actions cannot generate a real incoming FaceTime call or validate the live Notification Center Accessibility hierarchy. Complete this checklist on every target macOS version before enabling automatic actions.

Do not use real customer or production phone numbers in committed test records. Keep completed logs outside the repository unless every personal value is redacted.

## Test record

Copy this block into a private test note or issue:

```text
Commit SHA:
Date:
Tester:
Mac model:
Architecture: Apple silicon / Intel
macOS version:
FaceTime version/build if visible:
Run mode: detector / answer-trusted / gatekeeper
Identity source: local JSON / HTTPS
Contacts authorization: full / limited / denied / restricted
Accessibility entry path:
Refresh interval:
Maximum stale duration:
```

For each scenario record:

```text
Scenario:
Test caller presentation: raw number / saved full name / nickname / hidden or missing
Expected result:
Actual result:
Relevant privacy-safe logs:
Pass / Fail:
Notes:
```

## Before testing

1. Stop every existing FaceTime Picker process.
2. Pull or check out the exact commit being tested.
3. Configure a test-only identity source.
4. Run:

   ```zsh
   zsh "./Validate Core Logic.command"
   zsh ./build.sh
   ```

5. Remove and re-add `build/FaceTimePicker` in Accessibility settings if the executable was rebuilt and permission is uncertain.
6. Confirm the detector reaches:

   ```text
   TRUSTED IDENTITIES LOADED
   FOCUSED WINDOW POLL READY
   IDENTITY REFRESH READY
   READ-ONLY DETECTOR ENABLED
   ```

7. Confirm default logging is active. Do not enable `--log-caller-text` unless a scenario cannot be diagnosed otherwise.

## Phase 1: detector

The detector must never press Answer or Decline.

| ID | Scenario | Expected detector result |
|---|---|---|
| D1 | Trusted caller displayed as raw phone number | `CALL DETECTED`, trusted state, phone-number match source, no action. |
| D2 | Trusted caller displayed as a unique saved full name | `CALL DETECTED`, trusted state, unique-alias match source, no action. |
| D3 | Trusted caller displayed as a unique nickname | `CALL DETECTED`, trusted state, unique-alias match source, no action. |
| D4 | Explicit untrusted raw phone number | Detected as untrusted, no action. |
| D5 | Explicit untrusted saved name | Detected as untrusted, no action. |
| D6 | Trusted alias shared by another local contact | Detected as ambiguous, no action. |
| D7 | Caller identity initially missing and then appears | Candidate or pending unverified state followed by correct detection, no action. |
| D8 | Caller identity remains missing or generic | Unverified candidate/detection behavior, no action. |
| D9 | FaceTime audio call | Correct classification, no action. |
| D10 | FaceTime video call | Correct classification, no action. |
| D11 | Repeated Notification Center changes for one call | One logical detection; no duplicate action because detector never acts. |
| D12 | Call disappears before inspection completes | No stale action and monitor returns to idle behavior. |

### Contacts permission variants

Repeat at least D1–D3 with:

- full Contacts access
- denied Contacts access
- limited Contacts access containing the trusted contact
- limited Contacts access excluding the trusted contact

Expected behavior:

- raw-number matching continues without Contacts access
- saved-name matching works only when the trusted contact is accessible
- ambiguous aliases remain untrusted

### Phase 1 acceptance criteria

Proceed only when:

- trusted and untrusted callers are consistently distinguished
- the detector never presses a call control
- raw-number and saved-name limitations are understood
- no unexplained caller is classified as trusted
- default logs contain no caller text, endpoint URL, or credentials
- both audio and video calls have been tested

Then create the local proof marker:

```zsh
zsh "./Mark Phase 1 Proven.command"
```

## Phase 2: trusted answer

Start with:

```zsh
zsh "./Build and Run Trusted Answer.command"
```

Type `ENABLE` only after reviewing the warning.

| ID | Scenario | Expected result |
|---|---|---|
| A1 | Trusted raw phone number | Answer exactly once. |
| A2 | Trusted unique saved name | Answer exactly once. |
| A3 | Trusted unique nickname | Answer exactly once. |
| A4 | Explicit untrusted raw number | Leave ringing. |
| A5 | Explicit untrusted saved name | Leave ringing. |
| A6 | Ambiguous trusted alias | Leave ringing. |
| A7 | Missing or generic identity | Leave ringing. |
| A8 | Two rapid Accessibility event bursts for one trusted call | Answer once, not twice. |
| A9 | Second trusted call after the first call ends | Answer the second call normally. |
| A10 | Contacts permission removed before restart | Raw number may answer; saved name must not be trusted. |

### Phase 2 safety checks

- Confirm camera and microphone exposure is acceptable for auto-answer.
- Confirm an untrusted caller is never declined in this mode.
- Stop immediately if an untrusted or ambiguous caller is answered.
- Reproduce any failure in detector mode before continuing.

### Phase 2 acceptance criteria

Proceed only when:

- all trusted presentations answer reliably
- every untrusted, ambiguous, and unverified presentation remains ringing
- no call receives duplicate Answer presses
- behavior is consistent across audio and video calls

Then create the local proof marker:

```zsh
zsh "./Mark Phase 2 Proven.command"
```

## Phase 3: full gatekeeper

Start with:

```zsh
zsh "./Build and Run Gatekeeper.command"
```

Type `ENABLE GATEKEEPER` only after reviewing the warning.

| ID | Scenario | Expected result |
|---|---|---|
| G1 | Trusted raw phone number | Answer immediately and exactly once. |
| G2 | Trusted unique saved name | Answer immediately and exactly once. |
| G3 | Explicit untrusted raw number | Decline immediately and exactly once. |
| G4 | Explicit untrusted saved name | Decline immediately and exactly once. |
| G5 | Ambiguous trusted alias | Decline immediately and exactly once. |
| G6 | Identity initially missing, then becomes trusted within 900 ms | Answer after reinspection; do not decline first. |
| G7 | Identity initially missing, then becomes an explicit non-match within 900 ms | Decline after reinspection. |
| G8 | Identity remains missing past 900 ms | Decline once with identity-grace-expired behavior. |
| G9 | Call disappears during the grace period | No late Decline press on an unrelated surface. |
| G10 | Repeated events for one untrusted call | Decline once. |
| G11 | A new call arrives shortly after a previous action | Correctly classify the new call after cooldown. |
| G12 | Audio and video variants | Same trust decision in both call types. |

### Phase 3 acceptance criteria

- trusted calls answer
- explicit non-matches decline
- ambiguous aliases decline
- only missing/generic identity receives the grace delay
- identity that appears during the grace period is reevaluated correctly
- no action occurs after the call surface disappears
- no duplicate button press occurs

## Identity-source validation

These tests can be run in detector mode.

| ID | Source scenario | Expected result |
|---|---|---|
| S1 | Valid canonical envelope | Startup succeeds. |
| S2 | Valid bare array | Startup succeeds. |
| S3 | Valid snake_case fields | Startup succeeds. |
| S4 | Both file and URL variables set | Startup fails before monitoring. |
| S5 | Neither source variable set | Startup fails before monitoring. |
| S6 | HTTP endpoint instead of HTTPS | Startup fails before monitoring. |
| S7 | HTTP 401/403/500 | Startup or refresh fails. |
| S8 | Response larger than 256 KB | Reject response. |
| S9 | Unsupported schema version | Reject response. |
| S10 | One enabled invalid phone number among valid records | Reject the complete response. |
| S11 | Empty array or all records disabled | Reject as empty allowlist. |
| S12 | Duplicate formatted versions of the same digits | Load one normalized caller. |
| S13 | TTL below 30 | Refresh interval becomes 30 seconds unless overridden. |
| S14 | TTL above 86400 | Refresh interval becomes 86400 seconds unless overridden. |
| S15 | Missing mapped authentication environment variable | Startup fails with a configuration error. |

## Refresh and stale-cache testing

Use short allowed values for controlled testing, for example:

```zsh
export FACETIME_PICKER_MAX_STALE_SECONDS=60
# Invoke the binary directly in detector mode for a 30-second refresh interval.
build/FaceTimePicker --mode detector --refresh-seconds 30
```

| ID | Refresh scenario | Expected result |
|---|---|---|
| R1 | Provider changes trusted number and next refresh succeeds | Identity counts update and new caller rules apply. |
| R2 | One refresh fails and provider recovers before stale deadline | Previous snapshot remains active, then update succeeds. |
| R3 | Failures continue beyond stale deadline | `IDENTITY CACHE EXPIRED`; no caller remains trusted. |
| R4 | Source recovers after expiration | Identity index repopulates and trusted behavior returns. |
| R5 | Provider returns an empty list during refresh | Refresh fails; previous snapshot remains active until stale deadline. |
| R6 | Refresh interval is greater than requested maximum stale duration | Effective stale duration is at least the refresh interval. |

Do not run action modes with deliberately failing identity infrastructure until detector behavior has been confirmed.

## Privacy testing

Verify default logs do not contain:

- configured phone numbers
- resolved full names or nicknames
- endpoint URL
- request header names or values
- JSON response content

Then, in a private test only, verify `--log-caller-text` produces an explicit privacy warning. Stop and delete or protect those logs after the test.

## macOS update regression testing

After every major or minor macOS update that changes FaceTime or Notification Center:

1. Repeat all detector scenarios.
2. Compare `CALL CANDIDATE` missing fields with the previous result.
3. Repeat trusted-answer tests only after detector passes.
4. Repeat gatekeeper tests only after trusted-answer passes.
5. Record the exact macOS build number.

A green CI run is not a substitute for this regression test.

## Failure procedure

When any automatic action is wrong:

1. Press Control+C immediately.
2. Remove `.phase2-proven` to prevent accidental gatekeeper restart.
3. Reproduce the call in detector mode.
4. Save privacy-safe logs.
5. Record the test scenario and environment.
6. Open a bug report using the repository template.
7. Do not publish personal caller text or credentials.
