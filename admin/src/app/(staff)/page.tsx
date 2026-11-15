"use client";

import Link from "next/link";
import { useCallback, useEffect, useState } from "react";

import { Card, PageHeader, Spinner } from "@/components/ui";
import { useAuth } from "@/lib/auth";
import { loadDashboardCounts, type DashboardCounts } from "@/lib/dashboard";
import { friendlyError } from "@/lib/errors";

type Tile = {
  label: string;
  value: (counts: DashboardCounts) => number;
  href: string;
  hint: string;
  highlight?: (counts: DashboardCounts) => boolean;
};

const TILES: Tile[] = [
  {
    label: "New hiring requests",
    value: (c) => c.newHiringRequests,
    href: "/hiring-requests/",
    hint: "Submitted and not yet reviewed",
    highlight: (c) => c.newHiringRequests > 0,
  },
  {
    label: "Open hiring requests",
    value: (c) => c.openHiringRequests,
    href: "/hiring-requests/",
    hint: "Not completed, cancelled or rejected",
  },
  {
    label: "New enquiries",
    value: (c) => c.newEnquiries,
    href: "/enquiries/",
    hint: "“Request Info” messages to answer",
    highlight: (c) => c.newEnquiries > 0,
  },
  {
    label: "Published candidates",
    value: (c) => c.publishedCandidates,
    href: "/candidates/",
    hint: "Visible to customers in the app",
  },
];

export default function DashboardPage() {
  const { user } = useAuth();
  const [counts, setCounts] = useState<DashboardCounts | null>(null);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    setError(null);
    try {
      setCounts(await loadDashboardCounts());
    } catch (e) {
      setError(friendlyError(e));
    }
  }, []);

  useEffect(() => {
    // Loading data when the page opens is this effect's purpose.
    // eslint-disable-next-line react-hooks/set-state-in-effect
    void load();
  }, [load]);

  return (
    <>
      <PageHeader title="Dashboard" subtitle={`Signed in as ${user?.email ?? ""}`} />

      {error ? (
        <Card className="max-w-xl">
          <p role="alert" className="text-sm text-danger">
            {error}
          </p>
          <button
            type="button"
            onClick={() => void load()}
            className="mt-3 rounded-lg bg-primary px-4 py-2 text-sm font-semibold text-white"
          >
            Try again
          </button>
        </Card>
      ) : !counts ? (
        <Spinner />
      ) : (
        <>
          {counts.testCandidates > 0 ? (
            <p className="mb-6 rounded-xl bg-warning/15 p-3 text-sm">
              {counts.testCandidates} TEST {counts.testCandidates === 1 ? "candidate is" : "candidates are"}{" "}
              still listed. Delete them before launch.
            </p>
          ) : null}
          <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
            {TILES.map((tile) => (
              <Link key={tile.label} href={tile.href} className="block">
                <Card
                  className={`h-full transition hover:shadow-md ${
                    tile.highlight?.(counts) ? "ring-2 ring-primary" : ""
                  }`}
                >
                  <p className="text-sm text-muted">{tile.label}</p>
                  <p className="mt-2 font-heading text-3xl font-semibold">{tile.value(counts)}</p>
                  <p className="mt-1 text-xs text-muted">{tile.hint}</p>
                </Card>
              </Link>
            ))}
          </div>
        </>
      )}
    </>
  );
}
