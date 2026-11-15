"use client";

import type { User } from "@supabase/supabase-js";
import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from "react";

import { friendlyError } from "./errors";
import { canUseAdminSite, type RoleId } from "./roles";
import { isSupabaseConfigured, supabase } from "./supabase";

export type AuthStatus =
  | "loading"
  | "signed-out"
  /** Signed in, but not a recruitment staff member (signed out again). */
  | "no-access"
  | "ready";

type AuthState = {
  status: AuthStatus;
  user: User | null;
  roles: RoleId[];
  /** Resolves with an error message, or null on success. */
  signIn: (email: string, password: string) => Promise<string | null>;
  signOut: () => Promise<void>;
};

const AuthContext = createContext<AuthState | null>(null);

async function loadRoles(userId: string): Promise<RoleId[]> {
  // Row Level Security returns only the user's own roles.
  const { data, error } = await supabase()
    .from("user_roles")
    .select("role_id")
    .eq("user_id", userId);
  if (error) throw error;
  return (data ?? []).map((row) => row.role_id as RoleId);
}

export function AuthProvider({ children }: { children: ReactNode }) {
  const [status, setStatus] = useState<AuthStatus>(
    isSupabaseConfigured ? "loading" : "signed-out",
  );
  const [user, setUser] = useState<User | null>(null);
  const [roles, setRoles] = useState<RoleId[]>([]);

  /** Checks the roles of [next]; non-staff accounts are signed out. */
  const applyUser = useCallback(async (next: User | null) => {
    if (!next) {
      setUser(null);
      setRoles([]);
      setStatus((current) => (current === "no-access" ? current : "signed-out"));
      return;
    }
    try {
      const nextRoles = await loadRoles(next.id);
      if (!canUseAdminSite(nextRoles)) {
        setStatus("no-access");
        await supabase().auth.signOut();
        return;
      }
      setUser(next);
      setRoles(nextRoles);
      setStatus("ready");
    } catch {
      setUser(null);
      setRoles([]);
      setStatus("signed-out");
    }
  }, []);

  useEffect(() => {
    if (!isSupabaseConfigured) return;
    const client = supabase();
    let active = true;
    client.auth.getSession().then(({ data }) => {
      if (active) void applyUser(data.session?.user ?? null);
    });
    const { data } = client.auth.onAuthStateChange((event, session) => {
      // Token refreshes keep the same user; nothing to re-check.
      if (event === "TOKEN_REFRESHED" || event === "INITIAL_SESSION") return;
      // Supabase advises against awaiting other Supabase calls inside this
      // callback, so the role check runs afterwards.
      setTimeout(() => {
        if (active) void applyUser(session?.user ?? null);
      }, 0);
    });
    return () => {
      active = false;
      data.subscription.unsubscribe();
    };
  }, [applyUser]);

  const signIn = useCallback(async (email: string, password: string) => {
    setStatus("loading");
    const { error } = await supabase().auth.signInWithPassword({
      email: email.trim(),
      password,
    });
    if (error) {
      setStatus("signed-out");
      return friendlyError(error);
    }
    // onAuthStateChange (SIGNED_IN) checks the roles.
    return null;
  }, []);

  const signOut = useCallback(async () => {
    await supabase().auth.signOut();
    setStatus("signed-out");
  }, []);

  const value = useMemo(
    () => ({ status, user, roles, signIn, signOut }),
    [status, user, roles, signIn, signOut],
  );
  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth(): AuthState {
  const context = useContext(AuthContext);
  if (!context) throw new Error("useAuth must be used inside <AuthProvider>.");
  return context;
}
