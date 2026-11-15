/** Roles defined in `public.roles` (see the roles_and_profiles migration). */
export type RoleId =
  | "super_admin"
  | "admin"
  | "recruitment_officer"
  | "booking_manager"
  | "visa_officer"
  | "finance_officer"
  | "service_provider"
  | "customer"
  | (string & {});

/** Roles allowed into the recruitment admin (A.1–A.4). */
export const ADMIN_SITE_ROLES: readonly RoleId[] = [
  "super_admin",
  "admin",
  "recruitment_officer",
];

const LABELS: Record<string, string> = {
  super_admin: "Super Administrator",
  admin: "Administrator",
  recruitment_officer: "Recruitment Officer",
  booking_manager: "Booking Manager",
  visa_officer: "Visa Officer",
  finance_officer: "Finance Officer",
  service_provider: "Service Provider",
  customer: "Customer",
};

export function canUseAdminSite(roles: readonly RoleId[]): boolean {
  return roles.some((role) => ADMIN_SITE_ROLES.includes(role));
}

/** The most senior role, for display ("Recruitment Officer"). */
export function primaryRoleLabel(roles: readonly RoleId[]): string {
  const order: RoleId[] = [
    ...ADMIN_SITE_ROLES,
    "booking_manager",
    "visa_officer",
    "finance_officer",
    "service_provider",
    "customer",
  ];
  const best = order.find((role) => roles.includes(role));
  return best ? (LABELS[best] ?? best) : "No role";
}
