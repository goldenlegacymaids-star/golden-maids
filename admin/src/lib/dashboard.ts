import { supabase } from "./supabase";

export type DashboardCounts = {
  newHiringRequests: number;
  openHiringRequests: number;
  newEnquiries: number;
  publishedCandidates: number;
  testCandidates: number;
};

/** Hiring statuses that need no more work. */
export const CLOSED_HIRING_STATUSES = ["completed", "cancelled", "rejected"] as const;

/** Waits for a `count: "exact", head: true` query and returns the count. */
async function total(
  query: PromiseLike<{ count: number | null; error: unknown }>,
): Promise<number> {
  const { count, error } = await query;
  if (error) throw error;
  return count ?? 0;
}

export async function loadDashboardCounts(): Promise<DashboardCounts> {
  const db = supabase();
  const head = { count: "exact", head: true } as const;

  const [newHiringRequests, openHiringRequests, newEnquiries, publishedCandidates, testCandidates] =
    await Promise.all([
      total(db.from("hiring_requests").select("id", head).eq("status", "submitted")),
      total(
        db
          .from("hiring_requests")
          .select("id", head)
          .not("status", "in", `(${CLOSED_HIRING_STATUSES.join(",")})`),
      ),
      total(db.from("candidate_enquiries").select("id", head).eq("status", "new")),
      total(
        db.from("candidates").select("id", head).eq("is_published", true).is("archived_at", null),
      ),
      total(db.from("candidates").select("id", head).eq("is_test", true)),
    ]);

  return { newHiringRequests, openHiringRequests, newEnquiries, publishedCandidates, testCandidates };
}
