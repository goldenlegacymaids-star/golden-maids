/** Turns Supabase / network errors into messages for staff. */
export function friendlyError(error: unknown): string {
  const e = error as { code?: string; message?: string; name?: string } | null;
  const code = e?.code ?? "";
  const message = e?.message ?? "";

  if (code === "invalid_credentials") return "Incorrect email or password.";
  if (code === "email_not_confirmed") {
    return "This email address has not been verified yet. Verify it in the Golden Maids app first.";
  }
  if (code === "over_request_rate_limit") {
    return "Too many attempts. Please wait a few minutes and try again.";
  }
  if (code === "42501") return "Your role is not allowed to do this.";
  if (code === "PGRST116") return "This record no longer exists.";
  if (/fetch|network|Failed to fetch|NetworkError/i.test(message) || e?.name === "AuthRetryableFetchError") {
    return "Cannot reach the server. Please check your internet connection.";
  }
  return "Something went wrong. Please try again.";
}
