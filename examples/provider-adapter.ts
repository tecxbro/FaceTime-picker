// Pseudocode for any database/provider. This function belongs in trusted
// server-side infrastructure, not in the macOS client.
//
// Replace authenticateRequest() and queryYourDatabase() with the provider's
// official server-side APIs. Keep administrator credentials on the server,
// authenticate before querying, request only enabled rows, and return only the
// narrow versioned contract consumed by FaceTime Picker.
export async function getTrustedCallers(request: Request): Promise<Response> {
  // Reject unauthorized requests before accessing privileged database state.
  await authenticateRequest(request);

  // The adapter should apply the enabled filter at the provider when possible,
  // rather than loading a complete table and filtering sensitive rows in memory.
  const rows = await queryYourDatabase({ enabled: true });
  return Response.json({
    schemaVersion: 1,
    trustedCallers: rows.map((row) => ({
      id: String(row.id),
      phoneNumber: String(row.phone_number),
      enabled: Boolean(row.enabled),
    })),
    // The Mac caches this snapshot and performs no provider request while a call
    // is being decided. Runtime values are clamped to 30–86400 seconds.
    cacheTTLSeconds: 300,
  });
}

declare function authenticateRequest(request: Request): Promise<void>;
declare function queryYourDatabase(filter: { enabled: boolean }): Promise<Array<{
  id: string | number;
  phone_number: string;
  enabled: boolean;
}>>;
