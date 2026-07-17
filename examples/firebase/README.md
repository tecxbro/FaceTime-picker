# Firebase trusted-caller endpoint

This example exposes a second-generation Firebase HTTPS Cloud Function that returns enabled Firestore records in the FaceTime Picker identity contract.

The function uses the Firebase Admin SDK server-side and protects the endpoint with a Secret Manager-backed shared bearer token.

See Firebase's official documentation for [getting started with Cloud Functions](https://firebase.google.com/docs/functions/get-started), [HTTP functions](https://firebase.google.com/docs/functions/http-events), and [secret parameters](https://firebase.google.com/docs/functions/config-env#secret_parameters).

## Requirements

- A Firebase project with Cloud Firestore enabled.
- A project billing plan that supports deploying Cloud Functions. Firebase's current getting-started documentation requires the Blaze plan for deployment.
- Node.js and the Firebase CLI.
- Current `firebase-functions` and `firebase-admin` packages.

```zsh
npm install -g firebase-tools
firebase login
```

## Security model

```text
FaceTime Picker
  Authorization: Bearer <shared token>
            |
            v
Firebase HTTPS function
  FACETIME_PICKER_SHARED_TOKEN from Secret Manager
            |
            v
Firebase Admin SDK
            |
            v
trusted_callers collection
```

The Admin SDK has privileged Firestore access and does not rely on client Firestore Security Rules. Keep all administrative credentials and service identities inside Firebase/Google Cloud.

## 1. Initialize Firebase

From a new or existing project directory:

```zsh
firebase init firestore
firebase init functions
```

Choose JavaScript if you want to use [`cloud-function.js`](cloud-function.js) without conversion.

Inside the generated `functions` directory, keep the SDKs current:

```zsh
npm install firebase-functions@latest firebase-admin@latest --save
```

Copy the example into the generated function entry file or import/export it from that entry point.

## 2. Create the Firestore collection

Create a collection named:

```text
trusted_callers
```

Each document may use an automatically generated document ID and must contain:

| Field | Type | Required | Example |
|---|---|---:|---|
| `phoneNumber` | string | Yes | `+1 202 555 0147` |
| `enabled` | boolean | Yes for the example query | `true` |

The function returns the Firestore document ID as the response `id`.

Example document:

```json
{
  "phoneNumber": "+1 202 555 0147",
  "enabled": true
}
```

The FaceTime Picker client removes punctuation and requires 7–15 digits in every enabled number.

## 3. Add the shared secret

The example declares:

```js
const sharedToken = defineSecret("FACETIME_PICKER_SHARED_TOKEN");
```

Set its value with the Firebase CLI:

```zsh
firebase functions:secrets:set FACETIME_PICKER_SHARED_TOKEN
```

Enter a long random value, for example one generated with:

```zsh
openssl rand -hex 32
```

The function binds the secret through:

```js
onRequest({ secrets: [sharedToken] }, ...)
```

This binding is required. A secret is available only to functions that explicitly bind it.

Firebase's current guidance also requires redeploying functions that reference a secret after setting a new secret value.

## 4. Deploy

From the Firebase project root:

```zsh
firebase use YOUR_PROJECT_ID
firebase deploy --only functions
```

The CLI prints the deployed URL. Depending on region and generation, it resembles:

```text
https://REGION-YOUR_PROJECT_ID.cloudfunctions.net/trustedCallers
```

Use the exact URL printed by the Firebase CLI rather than constructing it manually.

## 5. Verify the endpoint

```zsh
export FACETIME_PICKER_SHARED_TOKEN='replace-with-the-same-token'
export FIREBASE_FUNCTION_URL='https://REGION-YOUR_PROJECT_ID.cloudfunctions.net/trustedCallers'

curl --fail-with-body \
  --silent \
  --show-error \
  --header "Accept: application/json" \
  --header "Authorization: Bearer $FACETIME_PICKER_SHARED_TOKEN" \
  "$FIREBASE_FUNCTION_URL" \
  | python3 -m json.tool
```

Expected shape:

```json
{
  "schemaVersion": 1,
  "trustedCallers": [
    {
      "id": "firestore-document-id",
      "phoneNumber": "+1 202 555 0147",
      "enabled": true
    }
  ],
  "cacheTTLSeconds": 300
}
```

Verify authentication failure as well:

```zsh
curl --include \
  --header "Authorization: Bearer wrong-token" \
  "$FIREBASE_FUNCTION_URL"
```

The response should be `401 Unauthorized`.

## 6. Configure FaceTime Picker

In the terminal that launches FaceTime Picker:

```zsh
export FACETIME_PICKER_IDENTITY_URL="$FIREBASE_FUNCTION_URL"
export FACETIME_PICKER_HEADER_ENVS="Authorization=FACETIME_PICKER_AUTHORIZATION"
export FACETIME_PICKER_AUTHORIZATION="Bearer $FACETIME_PICKER_SHARED_TOKEN"

zsh "./Build and Run Detector.command"
```

Do not copy Firebase service-account credentials or Admin SDK configuration into the FaceTime Picker environment.

## Firestore rules and IAM

The example reads Firestore through the Admin SDK. Admin SDK calls are authorized through the deployed function's service identity and bypass Firestore client Security Rules.

Protect the system by:

- limiting who can deploy or modify the function
- limiting who can modify `trusted_callers`
- binding the shared secret only to this function
- requiring the shared bearer token in the function
- reviewing function logs without logging the token or full caller list
- using least-privilege Google Cloud IAM where practical

Do not make the `trusted_callers` collection publicly readable merely to support this function.

## Updating callers

Firestore changes become visible after FaceTime Picker's next identity refresh. The example suggests a 300-second interval.

An empty result is rejected by the client. If every document is disabled, the previous valid snapshot may remain active until its stale deadline. Stop FaceTime Picker for immediate local revocation.

## Local testing

Firebase supports the Local Emulator Suite for HTTP functions and Firestore.

For a local secret override, follow Firebase's current emulator guidance, which supports a `.secret.local` file. Keep that file out of Git.

Test the local function with the same bearer header and contract checks used for production.

## Troubleshooting

### Deployment says the project must be upgraded

Cloud Functions deployment requires the billing plan identified by Firebase's current getting-started documentation. Review the Firebase project billing settings before continuing.

### `401 Unauthorized`

- Confirm the Mac and Secret Manager values match.
- Include the `Bearer ` prefix.
- Redeploy the function after setting or rotating the secret.

### Function cannot access the secret

Confirm the function binds `sharedToken` in the `secrets` option and has been redeployed after the secret was created or changed.

### `500` or `Database error`

- Confirm Cloud Firestore is initialized.
- Confirm the collection is named `trusted_callers`.
- Confirm the function's runtime service identity can access Firestore.
- Inspect Cloud Functions logs.

### Empty allowlist

Confirm at least one document has `enabled: true` and a valid string `phoneNumber`.

### Firestore query returns no documents despite records

The example uses `.where("enabled", "==", true)`. Records with a missing, false, or non-boolean `enabled` field do not match that query.
