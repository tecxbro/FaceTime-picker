import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
Deno.serve(async (request) => {
  const expected = Deno.env.get("FACETIME_PICKER_SHARED_TOKEN");
  if (!expected || request.headers.get("authorization") !== `Bearer ${expected}`) {
    return new Response("Unauthorized", { status: 401 });
  }
  const client = createClient(
    Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false } },
  );
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
