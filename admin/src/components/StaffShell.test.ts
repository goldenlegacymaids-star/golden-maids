import { describe, expect, it, vi } from "vitest";

// The shell's helpers are tested without rendering React.
vi.mock("@/lib/auth", () => ({ useAuth: () => ({}) }));

import { isActive, NAV_ITEMS } from "./StaffShell";

describe("navigation", () => {
  it("highlights the current section, including sub-pages", () => {
    expect(isActive("/", "/")).toBe(true);
    expect(isActive("/candidates/", "/")).toBe(false);
    expect(isActive("/candidates/", "/candidates/")).toBe(true);
    expect(isActive("/candidates/edit/", "/candidates/")).toBe(true);
    expect(isActive("/enquiries/", "/candidates/")).toBe(false);
  });

  it("links every section with a trailing slash (static hosting)", () => {
    for (const item of NAV_ITEMS) expect(item.href.endsWith("/")).toBe(true);
  });
});
