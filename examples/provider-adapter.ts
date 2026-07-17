// Pseudocode for any database/provider. Replace queryYourDatabase() with the
// provider's official server-side SDK. Never place database admin credentials
// in the macOS client.
export async function getTrustedCallers(request: Request): Promise<Response> {
  await authenticateRequest(request);
  const rows = await queryYourDatabase({ enabled: true });
  return Response.json({
    schemaVersion: 1,
    trustedCallers: rows.map((row) => ({
      id: String(row.id),
      phoneNumber: String(row.phone_number),
      enabled: Boolean(row.enabled),
    })),
    cacheTTLSeconds: 300,
  });
}

declare function authenticateRequest(request: Request): Promise<void>;
declare function queryYourDatabase(filter: { enabled: boolean }): Promise<Array<{
  id: string | number;
  phone_number: string;
  enabled: boolean;
}>>;
