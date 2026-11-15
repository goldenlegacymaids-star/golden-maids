import { describe, expect, it } from "vitest";

import { canUseAdminSite, primaryRoleLabel } from "./roles";

describe("staff access", () => {
  it("lets recruitment staff in", () => {
    expect(canUseAdminSite(["super_admin"])).toBe(true);
    expect(canUseAdminSite(["admin"])).toBe(true);
    expect(canUseAdminSite(["customer", "recruitment_officer"])).toBe(true);
  });

  it("keeps customers and other staff out of the recruitment admin", () => {
    expect(canUseAdminSite([])).toBe(false);
    expect(canUseAdminSite(["customer"])).toBe(false);
    expect(canUseAdminSite(["booking_manager", "visa_officer", "finance_officer"])).toBe(false);
  });

  it("shows the most senior role", () => {
    expect(primaryRoleLabel(["customer", "recruitment_officer"])).toBe("Recruitment Officer");
    expect(primaryRoleLabel(["admin", "super_admin"])).toBe("Super Administrator");
    expect(primaryRoleLabel([])).toBe("No role");
  });
});
