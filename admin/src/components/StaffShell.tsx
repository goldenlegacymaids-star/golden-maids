"use client";

import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { useEffect, useState, type ReactNode } from "react";

import { useAuth } from "@/lib/auth";
import { primaryRoleLabel } from "@/lib/roles";

import { Spinner } from "./ui";

export const NAV_ITEMS = [
  { href: "/", label: "Dashboard" },
  { href: "/hiring-requests/", label: "Hiring requests" },
  { href: "/enquiries/", label: "Enquiries" },
  { href: "/candidates/", label: "Candidates" },
  { href: "/prices/", label: "Prices & offers" },
] as const;

/** Whether [href] is the current section (`/candidates/x/` → Candidates). */
export function isActive(pathname: string, href: string): boolean {
  if (href === "/") return pathname === "/";
  return pathname.startsWith(href.replace(/\/$/, ""));
}

/**
 * Layout for signed-in staff: sidebar + page. Anyone else is sent to the
 * sign-in page. (The database enforces access as well.)
 */
export function StaffShell({ children }: { children: ReactNode }) {
  const { status, user, roles, signOut } = useAuth();
  const router = useRouter();
  const pathname = usePathname();
  const [menuOpen, setMenuOpen] = useState(false);

  useEffect(() => {
    if (status === "signed-out" || status === "no-access") {
      router.replace("/sign-in/");
    }
  }, [status, router]);

  if (status !== "ready") return <Spinner />;

  const nav = (
    <nav aria-label="Main" className="space-y-1">
      {NAV_ITEMS.map((item) => {
        const active = isActive(pathname, item.href);
        return (
          <Link
            key={item.href}
            href={item.href}
            onClick={() => setMenuOpen(false)}
            aria-current={active ? "page" : undefined}
            className={`block rounded-xl px-3 py-2.5 text-sm font-medium transition ${
              active ? "bg-primary text-white" : "text-ink hover:bg-light-blue"
            }`}
          >
            {item.label}
          </Link>
        );
      })}
    </nav>
  );

  const account = (
    <div className="border-t border-line pt-4 text-sm">
      <p className="truncate font-medium" title={user?.email ?? ""}>
        {user?.email}
      </p>
      <p className="text-muted">{primaryRoleLabel(roles)}</p>
      <button
        type="button"
        onClick={() => void signOut()}
        className="mt-3 rounded-lg border border-line px-3 py-1.5 text-sm hover:bg-light-blue"
      >
        Sign out
      </button>
    </div>
  );

  return (
    <div className="min-h-screen lg:flex">
      {/* Top bar on small screens */}
      <div className="flex items-center justify-between bg-white px-4 py-3 shadow-sm lg:hidden">
        {/* eslint-disable-next-line @next/next/no-img-element -- static export */}
        <img src="/logo.svg" alt="Golden Maids" className="h-8 w-auto" />
        <button
          type="button"
          aria-expanded={menuOpen}
          aria-controls="staff-menu"
          onClick={() => setMenuOpen((open) => !open)}
          className="rounded-lg border border-line px-3 py-1.5 text-sm"
        >
          Menu
        </button>
      </div>

      <aside
        id="staff-menu"
        className={`${menuOpen ? "block" : "hidden"} bg-white p-4 shadow-sm lg:sticky lg:top-0 lg:flex lg:h-screen lg:w-64 lg:flex-col lg:justify-between`}
      >
        <div>
          {/* eslint-disable-next-line @next/next/no-img-element -- static export */}
          <img src="/logo.svg" alt="Golden Maids" className="mb-6 hidden h-9 w-auto lg:block" />
          {nav}
        </div>
        <div className="mt-6">{account}</div>
      </aside>

      <main className="flex-1 p-6 lg:p-10">{children}</main>
    </div>
  );
}
