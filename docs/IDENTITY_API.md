# Trusted-caller identity API

FaceTime Picker loads a minimal trusted-caller allowlist from either a local JSON file or an HTTPS `GET` endpoint. The macOS client is provider-neutral: the service behind the endpoint may use Supabase, Firebase, PostgreSQL, MySQL, MongoDB, DynamoDB, Airtable, or another database.

The canonical contract is also available as [OpenAPI 3.1](../openapi/trusted-callers.yaml).

## Canonical response

Return HTTP `200` with `Content-Type: application/json` and this envelope:

```json
{
  "schemaVersion": 1,
  "trustedCallers": [
    {
      "id": "caller-123",
      "phoneNumber": "+1 202 555 0147",
      "enabled": true
    }
  ],
  "cacheTTLSeconds": 300
}
```

Use the envelope for new integrations. It provides explicit versioning and lets the provider suggest a refresh interval.

## Compatibility response formats

The current client also accepts a bare array:

```json
[
  {
    "id": "caller-123",
    "phoneNumber": "+1 202 555 0147",
    "enabled": true
  }
]
```

The following snake_case names are accepted for compatibility:

| Canonical | Compatibility alias |
|---|---|
| `schemaVersion` | `schema_version` |
| `trustedCallers` | `trusted_callers` |
| `cacheTTLSeconds` | `cache_ttl_seconds` |
| `phoneNumber` | `phone_number` |

Providers should emit one naming style consistently. The examples in this repository return the canonical camelCase envelope.

## Field reference

### Envelope

| Field | Type | Required | Behavior |
|---|---|---:|---|
| `schemaVersion` | integer | No | Defaults to `1`. Values other than `1` are rejected. |
| `trustedCallers` | array | Yes in practice | Missing or empty arrays are rejected because no enabled callers remain. |
| `cacheTTLSeconds` | integer | No | Suggested refresh interval. Values are clamped to `30`–`86400` seconds. |

### Trusted caller

| Field | Type | Required | Behavior |
|---|---|---:|---|
| `id` | string | No | Provider-owned identifier. The client does not use it for matching. |
| `phoneNumber` | string | Yes | Prefer E.164 display formatting. The client removes non-digits for validation and matching. |
| `enabled` | boolean | No | Defaults to `true`. Disabled records are ignored. |

## Validation behavior

The client validates the complete response before replacing the in-memory snapshot.

| Condition | Client behavior |
|---|---|
| HTTP status is not `200` | Reject the load or refresh. |
| Response exceeds 256 KB | Reject the response. |
| JSON is malformed | Reject the response. |
| Payload is neither an envelope nor a bare array | Reject the response. |
| `schemaVersion` is not `1` | Reject the response. |
| An enabled number contains fewer than 7 or more than 15 digits | Reject the entire response. |
| Duplicate normalized phone numbers | Keep the first occurrence. |
| `enabled` is missing | Treat the record as enabled. |
| A record is disabled | Ignore the record. |
| No enabled valid callers remain | Reject the response as an empty allowlist. |
| `cacheTTLSeconds` is below `30` | Clamp to `30`. |
| `cacheTTLSeconds` is above `86400` | Clamp to `86400`. |

The decoder currently ignores unknown JSON properties. The OpenAPI document reflects accepted response shapes but cannot express every runtime normalization rule.

## Phone-number matching

The client stores the provider's formatted value but compares digit-only variants.

For a number with at least 10 digits, matching includes the final 10 digits. A 10-digit value also receives a US-style leading-`1` variant. This accommodates common FaceTime and Contacts formatting differences, but providers should still store internationally unambiguous numbers whenever possible.

The provider does not send contact names. On the Mac, FaceTime Picker resolves configured phone numbers against local Contacts and trusts a displayed name or nickname only when that alias belongs to exactly one local contact.

## Authentication

Map arbitrary HTTP header names to environment variables:

```zsh
export FACETIME_PICKER_HEADER_ENVS="Authorization=MY_AUTH_HEADER,X-API-Key=MY_API_KEY"
export MY_AUTH_HEADER="Bearer secret-at-runtime"
export MY_API_KEY="secret-at-runtime"
```

For each comma-separated mapping:

- the left side is the outgoing HTTP header name
- the right side is the name of an environment variable
- the environment variable must exist and contain a non-empty value
- carriage returns and line feeds are rejected

Do not put credentials in:

- the endpoint URL
- repository files
- command-line arguments
- example JSON files

For long-lived use, load environment variables from a secret manager or a wrapper that reads macOS Keychain rather than storing secrets in shell history.

## HTTP behavior

The client:

- requires an `https://` endpoint
- sends `GET`
- sends `Accept: application/json`
- adds configured authentication headers
- accepts only HTTP `200`
- uses a default request timeout of 8 seconds
- clamps `FACETIME_PICKER_REQUEST_TIMEOUT_SECONDS` to 1–30 seconds
- bypasses local URL-cache data for each load

Redirect behavior follows the platform `URLSession` default. Providers should expose a stable final HTTPS endpoint and avoid relying on redirects for authentication-sensitive requests.

## Refresh and stale-cache behavior

The first successful response is required before monitoring starts.

After startup:

1. The allowlist is cached in memory.
2. No network request occurs in the incoming-call hot path.
3. Refreshes run on a utility queue at the active refresh interval.
4. A successful refresh re-resolves local Contacts aliases and replaces the monitor's identity index.
5. A failed refresh leaves the previous snapshot active until the effective stale deadline.
6. After the stale deadline, the identity index is cleared and no caller is trusted until recovery.

The active refresh interval is:

1. `--refresh-seconds`, when supplied; otherwise
2. clamped `cacheTTLSeconds`; otherwise
3. 300 seconds.

The effective maximum stale duration is the larger of:

- `FACETIME_PICKER_MAX_STALE_SECONDS` or `--max-stale-seconds`
- the active refresh interval

### Empty-list caveat

An empty allowlist is rejected as an invalid snapshot. It does **not** immediately replace the previous snapshot with an empty one. If a previous snapshot exists, it may remain active until the stale deadline.

For emergency revocation, do not rely solely on returning an empty array. Disable the endpoint or return an invalid response only with a stale deadline that matches your operational requirements, or stop the FaceTime Picker process on the Mac.

## Provider verification

Test the endpoint before configuring the macOS process:

```zsh
curl --fail-with-body \
  --silent \
  --show-error \
  --header "Accept: application/json" \
  --header "Authorization: Bearer replace-at-runtime" \
  "https://your-service.example/trusted-callers"
```

Confirm that:

- the response status is `200`
- the body is valid JSON
- at least one enabled caller is present
- every enabled number contains 7–15 digits after punctuation is removed
- no secret is present in the body or URL
- the complete body is smaller than 256 KB

Then configure the same endpoint and header mapping for FaceTime Picker.

## Provider compatibility

The macOS program intentionally has no knowledge of the backing database. A provider can use:

- a Supabase Edge Function
- a Firebase HTTPS Cloud Function
- a serverless function on another platform
- an API gateway transformation
- a narrow internal service
- a database REST interface whose output already matches a supported response shape

Keep the endpoint read-only and return only the fields needed by the client.

## Versioning

`schemaVersion: 1` is the only supported version.

A future incompatible contract must use a new version. Do not change the meaning of existing fields while continuing to return version `1`.

## Security requirements

- Use HTTPS for production.
- Authenticate the endpoint.
- Limit the service to reading enabled trusted-caller records.
- Keep database administrator or service-role credentials on the server side.
- Apply provider-side access controls, rate limits, and logging.
- Never expose a Supabase service-role/secret key or Firebase administrative credential to the macOS client.
- Avoid logging complete allowlist responses at the provider.

See [Security model](SECURITY_MODEL.md) for the client-side trust boundaries.
