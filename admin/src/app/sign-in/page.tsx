"use client";

import { useRouter } from "next/navigation";
import { useEffect, useState, type FormEvent } from "react";

import { useAuth } from "@/lib/auth";
import { isSupabaseConfigured } from "@/lib/supabase";

export default function SignInPage() {
  const { status, signIn } = useAuth();
  const router = useRouter();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    if (status === "ready") router.replace("/");
  }, [status, router]);

  async function onSubmit(event: FormEvent) {
    event.preventDefault();
    setError(null);
    if (!email.trim() || !password) {
      setError("Please enter your email and password.");
      return;
    }
    setBusy(true);
    const message = await signIn(email, password);
    setBusy(false);
    if (message) setError(message);
  }

  const noAccess = status === "no-access";

  return (
    <main className="flex min-h-screen items-center justify-center p-6">
      <div className="w-full max-w-sm">
        {/* eslint-disable-next-line @next/next/no-img-element -- static export */}
        <img src="/logo.svg" alt="Golden Maids" className="mx-auto mb-8 h-12 w-auto" />
        <div className="rounded-2xl bg-white p-6 shadow-[0_4px_20px_rgba(32,38,49,0.06)]">
          <h1 className="text-xl font-semibold">Staff sign in</h1>
          <p className="mt-1 text-sm text-muted">
            For Golden Legacy Domestic Workers Services staff only.
          </p>

          {!isSupabaseConfigured ? (
            <p role="alert" className="mt-4 rounded-xl bg-danger/10 p-3 text-sm text-danger">
              This website is not connected to Supabase. Copy <code>.env.example</code> to{" "}
              <code>.env.local</code>, fill in the values and restart.
            </p>
          ) : null}

          {noAccess ? (
            <p role="alert" className="mt-4 rounded-xl bg-warning/15 p-3 text-sm text-ink">
              This account doesn&apos;t have staff access. Ask a Super Administrator to give
              you a staff role.
            </p>
          ) : null}

          <form onSubmit={onSubmit} className="mt-5 space-y-4" noValidate>
            <label className="block">
              <span className="text-sm font-medium">Email</span>
              <input
                type="email"
                autoComplete="username"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                className="mt-1 w-full rounded-xl border border-line px-3 py-2.5 outline-none focus:border-primary focus:ring-2 focus:ring-primary/20"
              />
            </label>
            <label className="block">
              <span className="text-sm font-medium">Password</span>
              <input
                type="password"
                autoComplete="current-password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                className="mt-1 w-full rounded-xl border border-line px-3 py-2.5 outline-none focus:border-primary focus:ring-2 focus:ring-primary/20"
              />
            </label>
            {error ? (
              <p role="alert" className="text-sm text-danger">
                {error}
              </p>
            ) : null}
            <button
              type="submit"
              disabled={busy || !isSupabaseConfigured}
              className="w-full rounded-xl bg-primary py-3 font-semibold text-white transition hover:bg-secondary disabled:opacity-60"
            >
              {busy ? "Signing in…" : "Sign in"}
            </button>
          </form>
        </div>
        <p className="mt-6 text-center text-xs text-muted">
          Staff accounts are created in the Golden Maids app, then given a role by a Super
          Administrator.
        </p>
      </div>
    </main>
  );
}
