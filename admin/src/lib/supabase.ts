import { createClient, type SupabaseClient } from "@supabase/supabase-js";

const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
const publishableKey = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;

/** Whether `.env.local` has the Supabase settings. */
export const isSupabaseConfigured = Boolean(url && publishableKey);

let client: SupabaseClient | null = null;

/**
 * The browser's Supabase client (publishable key only). Every query is
 * checked by Row Level Security against the signed-in staff member's role.
 */
export function supabase(): SupabaseClient {
  if (!url || !publishableKey) {
    throw new Error(
      "Supabase is not configured. Copy .env.example to .env.local and fill in the values.",
    );
  }
  client ??= createClient(url, publishableKey, {
    auth: { persistSession: true, autoRefreshToken: true },
  });
  return client;
}
