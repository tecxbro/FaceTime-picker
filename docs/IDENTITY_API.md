# Trusted-caller identity API

## Contract

FaceTime Picker performs an HTTPS `GET` and accepts either an envelope:

```json
{
  "schemaVersion": 1,
  "trustedCallers": [
    { "id": "caller-123", "phoneNumber": "+1 202 555 0147", "enabled": true }
  ],
  "cacheTTLSeconds": 300
}
```

or a bare array using `phoneNumber` or `phone_number`. Supported envelope fields also accept camelCase or snake_case. `enabled` defaults to true. Disabled rows are ignored. Numbers must contain 7–15 digits after normalization, and duplicates are removed.

The response is limited to 256 KB. Unsupported schema versions, invalid numbers, malformed JSON, and empty allowlists are rejected.

## Authentication

Map arbitrary HTTP headers to environment variables:

```zsh
export FACETIME_PICKER_HEADER_ENVS="Authorization=MY_AUTH_HEADER,X-API-Key=MY_API_KEY"
export MY_AUTH_HEADER="Bearer secret-at-runtime"
export MY_API_KEY="secret-at-runtime"
```

Do not put credentials in the endpoint URL or repository files.

## Provider compatibility

The macOS program intentionally does not know whether data comes from Supabase, Firebase, PostgreSQL, MongoDB, DynamoDB, Airtable, or another system. The provider only needs to expose the documented JSON contract through HTTPS.

Options include a serverless/edge function, an API gateway transformation, or a database REST interface whose rows already match the bare-array schema.

## Refresh semantics

The first successful response is required before monitoring starts. The allowlist is cached in memory and refreshed periodically; no network request occurs in the incoming-call hot path. After the stale window expires, the app clears the allowlist and fails closed.

See `openapi/trusted-callers.yaml` for the machine-readable contract.
