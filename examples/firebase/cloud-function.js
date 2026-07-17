const { onRequest } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const admin = require("firebase-admin");
admin.initializeApp();
const sharedToken = defineSecret("FACETIME_PICKER_SHARED_TOKEN");
exports.trustedCallers = onRequest({ secrets: [sharedToken] }, async (req, res) => {
  if (req.get("authorization") !== `Bearer ${sharedToken.value()}`) {
    res.status(401).send("Unauthorized"); return;
  }
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
