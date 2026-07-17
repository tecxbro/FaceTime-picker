// Second-generation Firebase HTTPS function example. The Firebase Admin SDK
// stays server-side and uses the deployed function's service identity. The Mac
// receives only the separate shared endpoint token configured below.
const { onRequest } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const admin = require("firebase-admin");
admin.initializeApp();

// Firebase secret parameters are available only to functions that bind them in
// the `secrets` option. Redeploy this function after creating or rotating it.
const sharedToken = defineSecret("FACETIME_PICKER_SHARED_TOKEN");
exports.trustedCallers = onRequest({ secrets: [sharedToken] }, async (req, res) => {
  // Authenticate the narrow endpoint before performing the privileged Admin SDK query.
  if (req.get("authorization") !== `Bearer ${sharedToken.value()}`) {
    res.status(401).send("Unauthorized"); return;
  }
  // Return only enabled documents and only fields required by the public contract.
  const snapshot = await admin.firestore().collection("trusted_callers")
    .where("enabled", "==", true).get();
  res.json({
    schemaVersion: 1,
    trustedCallers: snapshot.docs.map((doc) => ({
      id: doc.id, phoneNumber: doc.get("phoneNumber"), enabled: true,
    })),
    cacheTTLSeconds: 300,
  });
});
