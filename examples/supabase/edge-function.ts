// Server-side Supabase Edge Function example. Deploy this function with
// gateway JWT verification disabled because it authenticates requests with the
// separate FACETIME_PICKER_SHARED_TOKEN below. See README.md in this directory.
//
// SUPABASE_SERVICE_ROLE_KEY is a legacy server-side key that bypasses Row Level
// Security. It must remain inside the hosted function and must never be sent to
// the FaceTime Picker macOS process.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
Deno.serve(async (request) => {
  // This shared token protects only the narrow trusted-caller endpoint. The Mac
  // receives this token at runtime, but never receives the database credential.
  const expected = Deno.env.get("FACETIME_PICKER_SHARED_TOKEN");
  if (!expected || request.headers.get("authorization") !== `Bearer ${expected}`) {
    return new Response("Unauthorized", { status: 401 });
  }
  const client = createClient(
    Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false } },
  );
  // Return only enabled rows and only the fields required by the public contract.
  const { data, error } = await client.from("trusted_callers")
    .select("id, phone_number, enabled").eq("enabled", true);
  if (error) return new Response("Database error", { status: 500 });
  return Response.json({
    schemaVersion: 1,
    trustedCallers: (data ?? []).map((row) => ({
      id: String(row.id), phoneNumber: row.phone_number, enabled: row.enabled,
    })),
    cacheTTLSeconds: 300,
  });
});
