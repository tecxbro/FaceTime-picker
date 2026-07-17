# Supabase trusted-caller endpoint

This example exposes a narrow Supabase Edge Function that returns enabled trusted callers in the FaceTime Picker identity contract.

The function keeps the database credential server-side and protects the endpoint with a separate shared bearer token supplied to the macOS process at runtime.

See Supabase's official documentation for [Edge Functions](https://supabase.com/docs/guides/functions), [function secrets](https://supabase.com/docs/guides/functions/secrets), and [deployment](https://supabase.com/docs/guides/functions/deploy).

## Security model

```text
FaceTime Picker
  Authorization: Bearer <shared token>
            |
            v
Supabase Edge Function
  SUPABASE_SERVICE_ROLE_KEY stays here
            |
            v
trusted_callers table
```

Never place `SUPABASE_SERVICE_ROLE_KEY`, a Supabase secret key, or a database password in the FaceTime Picker environment.

The existing example uses the legacy `SUPABASE_SERVICE_ROLE_KEY` environment variable. Supabase still provides it to hosted Edge Functions, but current Supabase documentation describes it as a legacy key and also supports newer secret-key configuration. The service-role key bypasses Row Level Security and must remain server-side.

## 1. Create the table

Run this SQL in a migration or the Supabase SQL editor:

```sql
create table if not exists public.trusted_callers (
  id uuid primary key default gen_random_uuid(),
  phone_number text not null,
  enabled boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists trusted_callers_enabled_idx
  on public.trusted_callers (enabled);
```

The client validates enabled phone numbers after removing punctuation. Each enabled value must contain 7–15 digits.

Insert test-only data:

```sql
insert into public.trusted_callers (phone_number, enabled)
values ('+1 202 555 0147', true);
```

Do not commit production phone numbers to this repository.

## 2. Create the Edge Function

From a Supabase CLI project:

```zsh
supabase functions new trusted-callers
```

Copy [`edge-function.ts`](edge-function.ts) to:

```text
supabase/functions/trusted-callers/index.ts
```

The example:

- compares the incoming `Authorization` header with a shared secret
- creates a server-side Supabase client
- selects only `id`, `phone_number`, and `enabled`
- filters to enabled rows
- returns the canonical camelCase version-1 envelope

## 3. Configure the shared token

Generate a long random value and set it as a Supabase function secret:

```zsh
openssl rand -hex 32
supabase secrets set FACETIME_PICKER_SHARED_TOKEN='replace-with-generated-value'
```

`SUPABASE_URL` and the legacy `SUPABASE_SERVICE_ROLE_KEY` are available automatically in hosted Edge Functions. Do not add the service-role value to a repository `.env` file.

For local development, use a local secrets file that is ignored by Git:

```text
FACETIME_PICKER_SHARED_TOKEN=replace-for-local-testing
```

Never commit that file.

## 4. Disable platform JWT verification for this function

The example authenticates with its own shared bearer token, not a Supabase Auth JWT. Supabase's gateway JWT verification must therefore be disabled for this individual function, or the gateway may reject the request before the function can compare `FACETIME_PICKER_SHARED_TOKEN`.

Use either method supported by the Supabase CLI.

### `supabase/config.toml`

```toml
[functions.trusted-callers]
verify_jwt = false
```

### Deployment flag

```zsh
supabase functions deploy trusted-callers --no-verify-jwt
```

Disabling gateway JWT verification does **not** make the example unauthenticated: the function still requires the exact shared bearer token. Protect that token like an API key.

## 5. Deploy

```zsh
supabase login
supabase projects list
supabase link --project-ref YOUR_PROJECT_REF
supabase functions deploy trusted-callers --no-verify-jwt
```

The deployed URL is:

```text
https://YOUR_PROJECT_REF.supabase.co/functions/v1/trusted-callers
```

## 6. Verify the endpoint

```zsh
export FACETIME_PICKER_SHARED_TOKEN='replace-with-the-same-token'

curl --fail-with-body \
  --silent \
  --show-error \
  --header "Accept: application/json" \
  --header "Authorization: Bearer $FACETIME_PICKER_SHARED_TOKEN" \
  "https://YOUR_PROJECT_REF.supabase.co/functions/v1/trusted-callers" \
  | python3 -m json.tool
```

Expected shape:

```json
{
  "schemaVersion": 1,
  "trustedCallers": [
    {
      "id": "00000000-0000-0000-0000-000000000000",
      "phoneNumber": "+1 202 555 0147",
      "enabled": true
    }
  ],
  "cacheTTLSeconds": 300
}
```

Also verify authentication failure:

```zsh
curl --include \
  --header "Authorization: Bearer wrong-token" \
  "https://YOUR_PROJECT_REF.supabase.co/functions/v1/trusted-callers"
```

The response should be `401 Unauthorized`.

## 7. Configure FaceTime Picker

In the terminal that will launch FaceTime Picker:

```zsh
export FACETIME_PICKER_IDENTITY_URL="https://YOUR_PROJECT_REF.supabase.co/functions/v1/trusted-callers"
export FACETIME_PICKER_HEADER_ENVS="Authorization=FACETIME_PICKER_AUTHORIZATION"
export FACETIME_PICKER_AUTHORIZATION="Bearer $FACETIME_PICKER_SHARED_TOKEN"

zsh "./Build and Run Detector.command"
```

Do not include `SUPABASE_SERVICE_ROLE_KEY` in these variables.

## Row Level Security

The service-role key bypasses Row Level Security, so RLS is not the protection boundary for this function. The important controls are:

- keep the service-role/secret key only inside the hosted function
- expose only the narrow enabled-caller query
- require the shared token
- rotate the shared token if disclosed
- review function logs without logging complete phone numbers or headers

You may still enable RLS on the table to protect access from browser or publishable-key clients:

```sql
alter table public.trusted_callers enable row level security;
```

Do not add a public read policy for this use case.

## Updating callers

Provider changes become visible after FaceTime Picker's next identity refresh. The example suggests a 300-second interval.

An empty effective allowlist is rejected by the client. For immediate local revocation, stop FaceTime Picker rather than relying on an empty response.

## Troubleshooting

### `401 Unauthorized`

- Confirm the Supabase secret and Mac environment use the same token.
- Include the `Bearer ` prefix in the Mac header value.
- Redeploy only when function code or configuration changes; Supabase secrets are available to hosted functions after being set according to current Supabase guidance.

### Gateway rejects the token before function logs appear

Deploy with `--no-verify-jwt` or set `verify_jwt = false` for this function. The shared token is not a Supabase Auth JWT.

### `500 Database error`

- Confirm the table exists in `public`.
- Confirm the column names are `id`, `phone_number`, and `enabled`.
- Inspect Supabase function logs.
- Confirm the hosted function has its default server-side Supabase credentials.

### FaceTime Picker reports an empty allowlist

Confirm at least one row has `enabled = true` and a phone number with 7–15 digits after punctuation is removed.

### Local function testing

When using `supabase functions serve`, supply the local shared secret through the CLI-supported environment/secrets mechanism and invoke the local function with the same Authorization header. Never point a local test at production caller data unless necessary and authorized.
