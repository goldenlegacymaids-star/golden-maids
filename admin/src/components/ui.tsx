import type { ReactNode } from "react";

export function Spinner({ label = "Loading…" }: { label?: string }) {
  return (
    <div role="status" className="flex items-center justify-center gap-3 p-10 text-muted">
      <span className="h-5 w-5 animate-spin rounded-full border-2 border-primary border-t-transparent" />
      <span>{label}</span>
    </div>
  );
}

export function Card({ children, className = "" }: { children: ReactNode; className?: string }) {
  return (
    <div className={`rounded-2xl bg-white p-5 shadow-[0_4px_20px_rgba(32,38,49,0.06)] ${className}`}>
      {children}
    </div>
  );
}

export function PageHeader({ title, subtitle }: { title: string; subtitle?: string }) {
  return (
    <header className="mb-6">
      <h1 className="text-2xl font-semibold text-ink">{title}</h1>
      {subtitle ? <p className="mt-1 text-sm text-muted">{subtitle}</p> : null}
    </header>
  );
}

export function ComingSoon({ title, what }: { title: string; what: string }) {
  return (
    <>
      <PageHeader title={title} />
      <Card className="max-w-xl">
        <span className="inline-block rounded-full bg-light-blue px-3 py-1 text-xs font-semibold text-primary">
          Coming soon
        </span>
        <p className="mt-3 text-sm text-muted">{what}</p>
      </Card>
    </>
  );
}
